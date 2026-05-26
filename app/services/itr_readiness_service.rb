# frozen_string_literal: true

# Builds ITR readiness checklist, suggested form, and default FY summary
# from SpendLens data + uploaded documents.
#
# The checklist is FORM-SPECIFIC — an ITR-1 filer doesn't see "upload
# your balance sheet" prompts, and an ITR-3 user does see business docs.
# Document inventory is built from ItrDocumentRegistry so adding a new
# doc type doesn't require touching this file.
class ItrReadinessService
  INCOME_THRESHOLD_ITR1 = 5_000_000
  SALARY_PATTERN = '(salary|salar|payroll|wages|stipend)'.freeze
  BUSINESS_PATTERN = '(freelance|consulting|invoice|client payment|business|gst|professional fees|contract)'.freeze

  # Kinds that actually realize a capital gain or loss for ITR purposes.
  # Buys / SIPs / contributions only deploy capital. See the regression
  # spec for the "ghost capital gains" bug this used to cause.
  REALIZING_KINDS = %w[sell transfer_out maturity].freeze

  def initialize(user, financial_year_start:)
    @user = user
    @prefs = UserPreference.new(user)
    @fy = financial_year_start.to_i
    @range = FinancialYear.range_for(@fy)
  end

  def call
    bank_txns = transactions_scope
    income = bank_txns.where(transaction_type: 'credit').sum(:amount).to_f
    expenses = bank_txns.where(transaction_type: 'debit').sum(:amount).to_f
    salary_credits = detect_salary_total
    business_income = detect_business_income

    inv_summary = investment_fy_summary
    docs_by_type = uploaded_docs_by_type
    suggested_form = suggest_itr_form(income, inv_summary, salary_credits, business_income)
    suggested_form_key = suggested_form[:form]

    documents = build_document_inventory(docs_by_type)
    deductions = aggregate_deductions(docs_by_type)
    checklist = build_checklist(
      form: suggested_form_key,
      income: income,
      salary_credits: salary_credits,
      inv_summary: inv_summary,
      docs_by_type: docs_by_type,
      deductions: deductions
    )
    readiness_pct = checklist_score(checklist)

    {
      financial_year_start: @fy,
      financial_year_label: FinancialYear.label(@fy),
      income: income,
      expenses: expenses,
      salary_estimate: salary_credits,
      business_income_estimate: business_income,
      net: income - expenses,
      investment_summary: inv_summary,
      documents: documents,
      deductions: deductions,
      suggested_itr_form: suggested_form,
      checklist: checklist,
      readiness_pct: readiness_pct,
      data_source: documents.values.any? { |d| d[:uploaded] } ? 'mixed' : 'generated',
    }
  end

  private

  def transactions_scope
    Transaction.for_user(@user.id, date_range: @range)
  end

  def detect_salary_total
    Transaction.sum_credits_matching_description(
      @user.id,
      date_range: @range,
      pattern: @prefs.description_pattern(SALARY_PATTERN, @prefs.salary_keywords)
    )
  end

  def detect_business_income
    Transaction.sum_credits_matching_description(
      @user.id,
      date_range: @range,
      pattern: @prefs.description_pattern(BUSINESS_PATTERN, @prefs.business_keywords)
    )
  end

  def investment_fy_summary
    txs = @user.investment_transactions.for_fy(@fy)
    has_realization = txs.where(kind: REALIZING_KINDS).exists?
    {
      transaction_count: txs.count,
      contributions: txs.where(kind: %w[contribution sip buy transfer_in]).sum(:amount).to_f,
      sells: txs.where(kind: REALIZING_KINDS).sum(:amount).to_f,
      dividends_interest: txs.where(kind: %w[dividend interest]).sum(:amount).to_f,
      holdings_count: @user.investment_holdings.count,
      has_capital_gains_events: has_realization,
      # Backward-compat alias (see itr_readiness_service_spec — both
      # report the same corrected semantics).
      has_capital_activity: has_realization,
    }
  end

  # Hash keyed by document_type, value = array of docs of that type (since
  # multi-instance types — Form 16A, LIC, rent receipts — can have many).
  def uploaded_docs_by_type
    @user.itr_tax_documents.for_fy(@fy).group_by(&:document_type)
  end

  # Frontend-facing inventory. For singleton types we collapse to a single
  # object (so existing UI keeps working); for multi-instance types we
  # surface count + list so the page can render "3 of 5 Form 16As" etc.
  def build_document_inventory(docs_by_type)
    ItrDocumentRegistry::ENTRIES.index_with do |entry|
      type = entry.key
      records = docs_by_type[type] || []
      first = records.first

      {
        type: type,
        label: entry.label,
        short_label: entry.short_label,
        category: entry.category,
        applicable_forms: entry.applicable_forms,
        multiple_per_fy: entry.multiple_per_fy,
        deduction_section: entry.deduction_section,
        deduction_cap: entry.deduction_cap == Float::INFINITY ? nil : entry.deduction_cap,
        uploaded: records.any?,
        count: records.size,
        status: first&.status,
        extraction_status: first&.extraction_status,
        extracted: records.any?(&:extracted?),
        ledger_synced: first&.ledger_synced_at.present?,
        id: first&.id,
        instances: records.map do |r|
          {
            id: r.id,
            label: r.display_label,
            payer_name: r.payer_name,
            source_label: r.source_label,
            extraction_status: r.extraction_status,
            extracted: r.extracted?,
          }
        end,
      }
    end.transform_keys(&:key)
  end

  # Aggregates deduction totals across the uploaded docs in each section,
  # capped at the section's statutory limit. Powers both the savings
  # advisor and the checklist's "80C cap utilised" hints.
  def aggregate_deductions(docs_by_type)
    result = {}

    ItrDocumentRegistry.deduction_entries_by_section.each do |section, entries|
      cap = ItrDocumentRegistry.cap_for(section)
      raw_total = entries.sum do |entry|
        (docs_by_type[entry.key] || []).sum do |doc|
          extract_amount_for_section(doc, entry)
        end
      end
      used = cap == Float::INFINITY ? raw_total : [raw_total, cap].min
      result[section] = {
        cap: cap == Float::INFINITY ? nil : cap,
        used: used.round(2),
        raw_total: raw_total.round(2),
        remaining: cap == Float::INFINITY ? nil : (cap - used).round(2),
        utilisation_pct: cap == Float::INFINITY ? nil : ((used / cap) * 100).round(1),
      }
    end

    result
  end

  # Best-effort amount extraction from a deduction doc. Each doc type uses
  # a different field name (premium_paid for LIC, amount_invested for ELSS,
  # interest_paid for home loan...) so the registry's ai_schema is the
  # source of allowable keys. We try the obvious matches.
  AMOUNT_KEYS = %w[
    amount amount_paid premium_paid amount_invested contributions_in_fy
    interest_paid principal_paid fees_paid annual_contribution annual_rent
  ].freeze

  def extract_amount_for_section(doc, _entry)
    data = doc.effective_data || {}
    AMOUNT_KEYS.each do |k|
      v = data[k] || data[k.to_s]
      return v.to_f if v.present? && v.to_f.positive?
    end
    0.0
  end

  def suggest_itr_form(income, inv_summary, salary_credits, business_income)
    if business_income.positive? && business_income >= salary_credits
      return {
        form: 'ITR-4',
        reason: 'Freelance/business-like credits detected — presumptive ITR-4 may apply if eligible; verify with a CA.',
      }
    end

    if business_income.positive?
      return {
        form: 'ITR-3',
        reason: 'Business or professional income patterns detected — ITR-3 may be required.',
      }
    end

    if inv_summary[:has_capital_gains_events]
      return {
        form: 'ITR-2',
        reason: 'Realized capital gains/losses detected this FY (sales / redemptions / maturities). ITR-1 cannot report Schedule CG — file ITR-2.',
      }
    end

    if income > INCOME_THRESHOLD_ITR1
      return {
        form: 'ITR-2',
        reason: "Total income above ₹#{(INCOME_THRESHOLD_ITR1 / 100_000).to_i} lakh exceeds the ITR-1 cap — file ITR-2.",
      }
    end

    if salary_credits.positive? || income.positive?
      return {
        form: 'ITR-1',
        reason: 'Salary-like income with no capital gains realizations — ITR-1 likely applies.',
      }
    end

    { form: 'ITR-1', reason: 'Upload Form 16 or statements to refine form selection.' }
  end

  # Form-specific checklist. Each entry is { id, label, done, hint?,
  # optional?, action_url? }. The frontend renders it linearly — order
  # matters for guidance flow.
  def build_checklist(form:, income:, salary_credits:, inv_summary:, docs_by_type:, deductions:)
    items = []

    # ----- Always-on items (every form) -----
    items << {
      id: 'statements',
      label: 'Bank statements uploaded',
      done: income.positive? || transactions_scope.exists?,
      hint: 'Upload statements for FY — without these we cannot reconcile income.',
    }

    items << {
      id: 'salary',
      label: 'Salary income identified',
      done: salary_credits.positive? || any_doc?(docs_by_type, 'form16'),
      hint: 'Upload Form 16, or make sure salary credits appear in your bank statements.',
    }

    items << {
      id: 'form16',
      label: doc_count_label('Form 16', docs_by_type, 'form16'),
      done: any_doc?(docs_by_type, 'form16'),
      optional: true,
      hint: 'Multiple employers in same FY? Upload one Form 16 per employer.',
    }

    items << {
      id: 'form16a',
      label: doc_count_label('Form 16A (TDS on FD interest, rent, professional fees)', docs_by_type, 'form16a'),
      done: any_doc?(docs_by_type, 'form16a'),
      optional: true,
      hint: 'One per bank or deductor. Drives Schedule TDS2 reconciliation.',
    }

    items << {
      id: 'interest_cert',
      label: doc_count_label('Bank interest certificates (savings / FD / RD)', docs_by_type, 'interest_cert'),
      done: any_doc?(docs_by_type, 'interest_cert'),
      optional: true,
      hint: 'Crosses-checks "Income from other sources" against AIS.',
    }

    items << {
      id: 'ais',
      label: 'AIS uploaded',
      done: any_doc?(docs_by_type, 'ais'),
      optional: true,
      hint: 'Download from incometax.gov.in → e-File → Annual Information Statement.',
    }

    items << {
      id: 'tis',
      label: 'TIS uploaded',
      done: any_doc?(docs_by_type, 'tis'),
      optional: true,
      hint: 'De-duped summary of AIS — much easier to read.',
    }

    items << {
      id: 'form26as',
      label: 'Form 26AS uploaded',
      done: any_doc?(docs_by_type, 'form26as'),
      optional: true,
      hint: 'Download from TRACES portal — confirms TDS credits.',
    }

    # ----- Investments / capital gains (ITR-2 and ITR-3) -----
    if %w[ITR-2 ITR-3].include?(form)
      items << {
        id: 'broker_pl',
        label: doc_count_label('Broker tax P&L (Zerodha / Groww / Upstox)', docs_by_type, 'broker_pl'),
        done: any_doc?(docs_by_type, 'broker_pl'),
        optional: true,
        hint: 'One per broker. Auto-syncs sells to your portfolio.',
      }
      items << {
        id: 'mf_cg',
        label: doc_count_label('Mutual fund capital gains (CAMS / KFintech)', docs_by_type, 'mf_cg'),
        done: any_doc?(docs_by_type, 'mf_cg'),
        optional: true,
      }
      items << {
        id: 'cas',
        label: 'Depository CAS (CDSL or NSDL)',
        done: any_doc?(docs_by_type, 'cas_cdsl') || any_doc?(docs_by_type, 'cas_nsdl'),
        optional: true,
        hint: 'Single statement that consolidates ALL brokers and AMCs.',
      }
      items << {
        id: 'crypto_pnl',
        label: 'Crypto / VDA tax report',
        done: any_doc?(docs_by_type, 'crypto_pnl'),
        optional: true,
        hint: 'Required when you traded crypto — Schedule VDA.',
      } if inv_summary[:holdings_count].positive? || any_doc?(docs_by_type, 'crypto_pnl')

      items << {
        id: 'property_deed',
        label: 'Property sale / purchase deed',
        done: any_doc?(docs_by_type, 'property_sale_deed'),
        optional: true,
      } if any_doc?(docs_by_type, 'property_sale_deed')
    end

    # ----- Investments tracked at all -----
    items << {
      id: 'investments',
      label: 'Investment activity tracked',
      done: inv_summary[:transaction_count].positive? || inv_summary[:holdings_count].positive?,
      optional: true,
      hint: 'Review investment suggestions in the Investments tab.',
    }

    items << {
      id: 'capital_gains',
      label: 'Capital gains documented (if applicable)',
      done: !inv_summary[:has_capital_gains_events] ||
            any_doc?(docs_by_type, 'broker_pl') ||
            any_doc?(docs_by_type, 'mf_cg') ||
            inv_summary[:sells].positive?,
      optional: true,
    }

    # ----- Deduction proofs (only meaningful under OLD regime) -----
    items << deduction_item('80c', '80C investments (LIC / ELSS / PPF / NSC / tuition)', deductions['80C'])
    items << deduction_item('80d', '80D health insurance', deductions['80D'])
    items << deduction_item('80ccd1b', '80CCD(1B) NPS Tier-I (extra ₹50k)', deductions['80CCD(1B)'])
    items << deduction_item('80e', '80E education loan interest', deductions['80E'])
    items << deduction_item('80g', '80G donation receipts', deductions['80G'])

    items << {
      id: 'home_loan',
      label: 'Home loan interest certificate (Section 24b)',
      done: any_doc?(docs_by_type, 'home_loan_cert'),
      optional: true,
      hint: 'Lender-issued P+I split — principal goes to 80C, interest to Section 24(b).',
    }

    items << {
      id: 'rent',
      label: 'Rent receipts (HRA / 80GG)',
      done: any_doc?(docs_by_type, 'rent_receipt'),
      optional: true,
      hint: 'Landlord PAN required if annual rent > ₹1 lakh.',
    }

    # ----- Business / ITR-3 / ITR-4 only -----
    if %w[ITR-3 ITR-4].include?(form)
      items << {
        id: 'business_pl',
        label: 'P&L statement',
        done: any_doc?(docs_by_type, 'business_pl'),
        hint: 'Required for ITR-3 / 4. Upload your annual P&L.',
      }
      items << {
        id: 'balance_sheet',
        label: 'Balance sheet (as of 31-Mar)',
        done: any_doc?(docs_by_type, 'balance_sheet'),
        hint: 'Required for ITR-3 / 4 — closing assets and liabilities.',
      }
      items << {
        id: 'gst_summary',
        label: 'GST summary (GSTR-1 / 3B / 9)',
        done: any_doc?(docs_by_type, 'gst_summary'),
        optional: true,
      }
      items << {
        id: 'tax_audit',
        label: 'Tax audit report (Form 3CB-3CD)',
        done: any_doc?(docs_by_type, 'tax_audit_report'),
        optional: true,
        hint: 'Mandatory only if turnover crosses Section 44AB threshold.',
      }
    end

    # ----- Universal "good to have" -----
    items << {
      id: 'challan',
      label: 'Advance / self-assessment tax challans',
      done: any_doc?(docs_by_type, 'challan_tax_paid'),
      optional: true,
    }

    items
  end

  def deduction_item(id, label, used_section)
    cap = used_section&.dig(:cap)
    used = used_section&.dig(:used).to_f
    pct = used_section&.dig(:utilisation_pct)
    done = used.positive?
    hint =
      if cap && used.positive? && pct.to_f < 100
        "Used ₹#{used.to_i} of ₹#{cap.to_i} cap (#{pct}%). Top-up before 31-Mar to save more tax."
      elsif cap && used.zero?
        "Unused ₹#{cap.to_i} cap — full deduction available under OLD regime."
      elsif used.positive?
        "Used ₹#{used.to_i} so far (no upper cap)."
      end
    {
      id: "deduction_#{id}",
      label: label,
      done: done,
      optional: true,
      hint: hint,
    }
  end

  def any_doc?(docs_by_type, type)
    (docs_by_type[type] || []).any?
  end

  def doc_count_label(base, docs_by_type, type)
    n = (docs_by_type[type] || []).size
    n.positive? ? "#{base} (#{n} uploaded)" : base
  end

  def checklist_score(checklist)
    required = checklist.reject { |c| c[:optional] }
    optional = checklist.select { |c| c[:optional] }
    req_score = required.count { |c| c[:done] }
    opt_score = optional.count { |c| c[:done] }
    return 0 if required.empty?

    base = (req_score.to_f / required.size * 70).round
    bonus = optional.empty? ? 0 : (opt_score.to_f / optional.size * 30).round
    [base + bonus, 100].min
  end
end
