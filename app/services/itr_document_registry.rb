# frozen_string_literal: true

# Single source of truth for ITR tax document types.
#
# Each entry describes a kind of document a user can upload for their
# annual return. The registry powers:
#   * ItrTaxDocument's validation list and label_for helper
#   * The ITR readiness checklist (form-specific via :applicable_forms)
#   * The frontend upload UI (category grouping, accepted extensions,
#     multi-instance vs single-instance, badges)
#   * TaxDocumentExtractorService AI schemas (one prompt per doc type)
#   * TaxSavingsAdvisorService (deduction sections + caps)
#
# Categories — used to group the upload screen and to drive checklist
# rendering. They roughly mirror what ClearTax / Quicko / TaxBuddy
# present as separate sections:
#
#   :prefill           — Form 16, AIS, TIS, 26AS (auto-populate the return)
#   :income            — Form 16A, 16B, interest cert, dividend statements,
#                        pension, rent received certs
#   :capital_gains     — Broker P&L, MF CG, CDSL/NSDL CAS, crypto, property
#   :business          — ITR-3/4 only — P&L, balance sheet, GST, audit
#   :deduction_proof   — 80C/D/E/G/EE/EEA/U/DDB/CCD(1B)/TTA/TTB/GG
#   :other             — Form 10E (relief 89), Form 12BB, 15G/15H, misc
#
# applicable_forms — which ITR forms can legitimately include this
# document. Used to filter the checklist so an ITR-1 filer doesn't see
# "upload your balance sheet" suggestions.
#
# multiple_per_fy — true when a user can have more than one of this doc
# per FY (Form 16A from many banks, multiple rent receipts, etc.). False
# for singletons like Form 16, AIS, 26AS where the IT dept issues one.
#
# deduction_section / deduction_cap — populated for :deduction_proof docs
# so the savings advisor can compute "you've used ₹X of the ₹Y cap".
#
# ai_schema — minimal JSON schema fed to the LLM during extraction. Keys
# only; types are coerced downstream. Keep deliberately small to keep the
# extraction prompt cheap.
class ItrDocumentRegistry
  Entry = Struct.new(
    :key, :label, :short_label, :category, :description,
    :accept, :multiple_per_fy, :applicable_forms,
    :schedule, :deduction_section, :deduction_cap,
    :ai_schema, :tier,
    keyword_init: true
  )

  ALL_FORMS = %w[ITR-1 ITR-2 ITR-3 ITR-4].freeze

  # ===========================================================================
  # TIER 1 — Prefill / reconciliation artifacts
  # The IT dept's own data sources. Highest auto-population leverage.
  # ===========================================================================
  ENTRIES = [
    Entry.new(
      key: 'form16',
      label: 'Form 16 (Salary TDS Certificate)',
      short_label: 'Form 16',
      category: :prefill,
      description: 'Issued by your employer. Auto-fills salary, exemptions, deductions and TDS.',
      accept: '.pdf,.json',
      multiple_per_fy: true, # multiple employers in same FY
      applicable_forms: ALL_FORMS,
      schedule: 'Salary',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 1,
      ai_schema: %w[employer pan salary basic_salary hra_received lta exemptions deductions_80c deductions_80d hra_exemption professional_tax standard_deduction tds period_start period_end]
    ),

    Entry.new(
      key: 'ais',
      label: 'Annual Information Statement (AIS)',
      short_label: 'AIS',
      category: :prefill,
      description: 'IT-dept consolidated view of all reported income. Download from incometax.gov.in.',
      accept: '.pdf,.json',
      multiple_per_fy: false,
      applicable_forms: ALL_FORMS,
      schedule: nil,
      deduction_section: nil,
      deduction_cap: nil,
      tier: 1,
      ai_schema: %w[salary interest dividends ltcg stcg foreign_remittance gst_turnover tds lines]
    ),

    Entry.new(
      key: 'tis',
      label: 'Taxpayer Information Summary (TIS)',
      short_label: 'TIS',
      category: :prefill,
      description: 'De-duplicated companion to AIS — often easier to read for reconciliation.',
      accept: '.pdf,.json',
      multiple_per_fy: false,
      applicable_forms: ALL_FORMS,
      schedule: nil,
      deduction_section: nil,
      deduction_cap: nil,
      tier: 1,
      ai_schema: %w[salary interest dividends ltcg stcg tds lines]
    ),

    Entry.new(
      key: 'form26as',
      label: 'Form 26AS (Tax Credit Statement)',
      short_label: 'Form 26AS',
      category: :prefill,
      description: 'TRACES tax credit ledger — TDS, TCS, advance tax, self-assessment tax.',
      accept: '.pdf,.json',
      multiple_per_fy: false,
      applicable_forms: ALL_FORMS,
      schedule: nil,
      deduction_section: nil,
      deduction_cap: nil,
      tier: 1,
      ai_schema: %w[total_tds total_tcs advance_tax self_assessment_tax tds_entries]
    ),

    # =========================================================================
    # TIER 2 — Income source documents
    # =========================================================================
    Entry.new(
      key: 'form16a',
      label: 'Form 16A (TDS on non-salary income)',
      short_label: 'Form 16A',
      category: :income,
      description: 'TDS certificate from banks (FD interest), tenants, professional clients, etc.',
      accept: '.pdf,.json',
      multiple_per_fy: true,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule TDS2',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 2,
      ai_schema: %w[deductor pan section income_paid tds_deducted period_start period_end]
    ),

    Entry.new(
      key: 'form16b',
      label: 'Form 16B (TDS on property sale — buyer issues)',
      short_label: 'Form 16B',
      category: :income,
      description: 'For property sellers. Buyer deducts 1% TDS on consideration > ₹50 lakh.',
      accept: '.pdf,.json',
      multiple_per_fy: true,
      applicable_forms: %w[ITR-2 ITR-3],
      schedule: 'Schedule CG',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 2,
      ai_schema: %w[buyer_name buyer_pan property_address consideration tds_deducted transfer_date]
    ),

    Entry.new(
      key: 'interest_cert',
      label: 'Bank Interest Certificate (FD / Savings / RD)',
      short_label: 'Interest cert',
      category: :income,
      description: 'Bank-issued interest summary for FY — used for "Income from other sources".',
      accept: '.pdf,.json',
      multiple_per_fy: true,
      applicable_forms: ALL_FORMS,
      schedule: 'Income from Other Sources',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 2,
      ai_schema: %w[bank_name account_type savings_interest fd_interest rd_interest tds_deducted]
    ),

    Entry.new(
      key: 'dividend_stmt',
      label: 'Dividend Statement',
      short_label: 'Dividends',
      category: :income,
      description: 'Listed-company dividend payouts. Indian dividends are taxable in hands of recipient since FY 20-21.',
      accept: '.pdf,.csv,.json',
      multiple_per_fy: true,
      applicable_forms: %w[ITR-1 ITR-2 ITR-3 ITR-4],
      schedule: 'Income from Other Sources',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 2,
      ai_schema: %w[entity isin dividend_amount payment_date tds_deducted]
    ),

    Entry.new(
      key: 'pension_stmt',
      label: 'Pension Statement / Passbook',
      short_label: 'Pension',
      category: :income,
      description: 'EPS / private pension payouts.',
      accept: '.pdf,.json',
      multiple_per_fy: false,
      applicable_forms: %w[ITR-1 ITR-2],
      schedule: 'Salary',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 2,
      ai_schema: %w[scheme_name annual_pension tds_deducted]
    ),

    Entry.new(
      key: 'salary_slip',
      label: 'Salary Slip (any month)',
      short_label: 'Salary slip',
      category: :income,
      description: 'Useful when Form 16 is unavailable — derives gross salary, HRA, PF.',
      accept: '.pdf,.json',
      multiple_per_fy: true,
      applicable_forms: %w[ITR-1 ITR-2],
      schedule: 'Salary',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 2,
      ai_schema: %w[employer month basic_salary hra special_allowance pf_employee professional_tax tds]
    ),

    # =========================================================================
    # TIER 3 — Capital gains / investment documents
    # =========================================================================
    Entry.new(
      key: 'broker_pl',
      label: 'Broker Tax P&L (Zerodha / Groww / Upstox)',
      short_label: 'Broker P&L',
      category: :capital_gains,
      description: 'Annual tax P&L from your stock broker. Syncs sells to your portfolio.',
      accept: '.pdf,.csv,.xlsx,.json',
      multiple_per_fy: true,
      applicable_forms: %w[ITR-2 ITR-3],
      schedule: 'Schedule CG',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 3,
      ai_schema: %w[broker total_turnover stcg ltcg intraday_pnl fno_pnl transactions]
    ),

    Entry.new(
      key: 'mf_cg',
      label: 'MF Capital Gains Statement (CAS / CG report)',
      short_label: 'MF CG',
      category: :capital_gains,
      description: 'CAMS / KFintech capital-gains report — STCG/LTCG per redemption.',
      accept: '.pdf,.csv,.xlsx,.json',
      multiple_per_fy: true,
      applicable_forms: %w[ITR-2 ITR-3],
      schedule: 'Schedule CG',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 3,
      ai_schema: %w[stcg ltcg transactions]
    ),

    Entry.new(
      key: 'cas_cdsl',
      label: 'CDSL Consolidated Account Statement',
      short_label: 'CDSL CAS',
      category: :capital_gains,
      description: 'All-broker depository holdings + transactions from CDSL.',
      accept: '.pdf',
      multiple_per_fy: true,
      applicable_forms: %w[ITR-2 ITR-3],
      schedule: 'Schedule CG',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 3,
      ai_schema: %w[isin scrip_name closing_balance market_value transactions]
    ),

    Entry.new(
      key: 'cas_nsdl',
      label: 'NSDL Consolidated Account Statement',
      short_label: 'NSDL CAS',
      category: :capital_gains,
      description: 'All-broker depository holdings + transactions from NSDL.',
      accept: '.pdf',
      multiple_per_fy: true,
      applicable_forms: %w[ITR-2 ITR-3],
      schedule: 'Schedule CG',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 3,
      ai_schema: %w[isin scrip_name closing_balance market_value transactions]
    ),

    Entry.new(
      key: 'crypto_pnl',
      label: 'Crypto / VDA Tax Report',
      short_label: 'Crypto P&L',
      category: :capital_gains,
      description: 'Schedule VDA — VDAs taxed at flat 30%, no loss offset.',
      accept: '.pdf,.csv,.xlsx,.json',
      multiple_per_fy: true,
      applicable_forms: %w[ITR-2 ITR-3],
      schedule: 'Schedule VDA',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 3,
      ai_schema: %w[exchange total_buys total_sells gross_gain tds_deducted transactions]
    ),

    Entry.new(
      key: 'property_sale_deed',
      label: 'Property Sale / Purchase Deed',
      short_label: 'Property deed',
      category: :capital_gains,
      description: 'Real-estate sale or purchase docs — needed for Schedule CG (land/building).',
      accept: '.pdf,.jpg,.jpeg,.png',
      multiple_per_fy: true,
      applicable_forms: %w[ITR-2 ITR-3],
      schedule: 'Schedule CG',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 3,
      ai_schema: %w[property_address transfer_date sale_value cost_of_acquisition indexed_cost improvement_cost]
    ),

    # =========================================================================
    # TIER 4 — Deduction proofs (Section 80 — Chapter VI-A)
    # =========================================================================
    Entry.new(
      key: 'lic_premium',
      label: 'LIC / Life Insurance Premium Receipt',
      short_label: 'LIC',
      category: :deduction_proof,
      description: 'Life insurance premium — eligible under Section 80C.',
      accept: '.pdf,.jpg,.jpeg,.png',
      multiple_per_fy: true,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule VI-A',
      deduction_section: '80C',
      deduction_cap: 150_000,
      tier: 4,
      ai_schema: %w[insurer policy_number premium_paid period_start period_end]
    ),

    Entry.new(
      key: 'elss_80c',
      label: 'ELSS Mutual Fund Statement',
      short_label: 'ELSS',
      category: :deduction_proof,
      description: 'Tax-saver mutual fund investment — Section 80C.',
      accept: '.pdf,.csv,.xlsx,.json',
      multiple_per_fy: true,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule VI-A',
      deduction_section: '80C',
      deduction_cap: 150_000,
      tier: 4,
      ai_schema: %w[fund_house scheme amount_invested folio period_start period_end]
    ),

    Entry.new(
      key: 'ppf_80c',
      label: 'PPF Passbook / Statement',
      short_label: 'PPF',
      category: :deduction_proof,
      description: 'Public Provident Fund — Section 80C.',
      accept: '.pdf,.jpg,.jpeg,.png',
      multiple_per_fy: false,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule VI-A',
      deduction_section: '80C',
      deduction_cap: 150_000,
      tier: 4,
      ai_schema: %w[account_number contributions_in_fy interest_credited closing_balance]
    ),

    Entry.new(
      key: 'sukanya_80c',
      label: 'Sukanya Samriddhi Account Statement',
      short_label: 'Sukanya',
      category: :deduction_proof,
      description: 'For girl child — Section 80C.',
      accept: '.pdf,.jpg,.jpeg,.png',
      multiple_per_fy: true,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule VI-A',
      deduction_section: '80C',
      deduction_cap: 150_000,
      tier: 4,
      ai_schema: %w[account_holder contributions_in_fy closing_balance]
    ),

    Entry.new(
      key: 'nsc_80c',
      label: 'NSC Investment Receipt',
      short_label: 'NSC',
      category: :deduction_proof,
      description: 'National Savings Certificate — Section 80C (principal + accrued interest).',
      accept: '.pdf,.jpg,.jpeg,.png',
      multiple_per_fy: true,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule VI-A',
      deduction_section: '80C',
      deduction_cap: 150_000,
      tier: 4,
      ai_schema: %w[certificate_number issue_date amount_invested]
    ),

    Entry.new(
      key: 'tuition_80c',
      label: 'School / College Tuition Fee Receipt',
      short_label: 'Tuition',
      category: :deduction_proof,
      description: 'Children\'s tuition fees — Section 80C (max 2 children).',
      accept: '.pdf,.jpg,.jpeg,.png',
      multiple_per_fy: true,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule VI-A',
      deduction_section: '80C',
      deduction_cap: 150_000,
      tier: 4,
      ai_schema: %w[institution student_name fees_paid period_start period_end]
    ),

    Entry.new(
      key: 'health_insurance_80d',
      label: 'Health Insurance Premium (Self / Family)',
      short_label: 'Health ins',
      category: :deduction_proof,
      description: 'Health insurance premium — Section 80D. Higher cap for senior parents.',
      accept: '.pdf,.jpg,.jpeg,.png',
      multiple_per_fy: true,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule VI-A',
      deduction_section: '80D',
      deduction_cap: 100_000, # 25k self + 25k spouse/kids + 50k senior parents
      tier: 4,
      ai_schema: %w[insurer policy_number premium_paid insured_relation period_start period_end]
    ),

    Entry.new(
      key: 'health_check_80d',
      label: 'Preventive Health Check-up Receipt',
      short_label: 'Health check',
      category: :deduction_proof,
      description: 'Preventive health check — Section 80D (cap ₹5,000 within 80D limit).',
      accept: '.pdf,.jpg,.jpeg,.png',
      multiple_per_fy: true,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule VI-A',
      deduction_section: '80D',
      deduction_cap: 5_000,
      tier: 4,
      ai_schema: %w[provider check_date amount_paid]
    ),

    Entry.new(
      key: 'nps_80ccd1b',
      label: 'NPS Tier-I Contribution (80CCD(1B))',
      short_label: 'NPS additional',
      category: :deduction_proof,
      description: 'Additional ₹50,000 over and above 80C — exclusive to NPS Tier-I.',
      accept: '.pdf,.csv,.json',
      multiple_per_fy: false,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule VI-A',
      deduction_section: '80CCD(1B)',
      deduction_cap: 50_000,
      tier: 4,
      ai_schema: %w[pran annual_contribution employer_contribution]
    ),

    Entry.new(
      key: 'medical_80ddb',
      label: 'Specified Illness Treatment Receipts',
      short_label: '80DDB',
      category: :deduction_proof,
      description: 'Treatment of specified illnesses (cancer, kidney failure, etc.) — Section 80DDB.',
      accept: '.pdf,.jpg,.jpeg,.png',
      multiple_per_fy: true,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule VI-A',
      deduction_section: '80DDB',
      deduction_cap: 100_000, # 40k normal / 1L senior
      tier: 4,
      ai_schema: %w[patient_relation hospital diagnosis amount_paid prescription_attached]
    ),

    Entry.new(
      key: 'disability_80u',
      label: 'Disability Certificate (Self / Dependent)',
      short_label: '80U/80DD',
      category: :deduction_proof,
      description: 'Disability deduction — Section 80U (self) or 80DD (dependent).',
      accept: '.pdf,.jpg,.jpeg,.png',
      multiple_per_fy: false,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule VI-A',
      deduction_section: '80U',
      deduction_cap: 125_000, # 75k normal / 1.25L severe
      tier: 4,
      ai_schema: %w[patient_relation severity issuing_authority issue_date]
    ),

    Entry.new(
      key: 'education_loan_80e',
      label: 'Education Loan Interest Certificate',
      short_label: '80E',
      category: :deduction_proof,
      description: 'Education loan interest — Section 80E (no upper cap, deductible up to 8 years).',
      accept: '.pdf,.json',
      multiple_per_fy: false,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule VI-A',
      deduction_section: '80E',
      deduction_cap: nil,
      tier: 4,
      ai_schema: %w[lender loan_account interest_paid principal_paid period_start period_end]
    ),

    Entry.new(
      key: 'home_loan_cert',
      label: 'Home Loan Interest Certificate',
      short_label: 'Home loan',
      category: :deduction_proof,
      description: 'Bank-issued P+I split — principal goes to 80C, interest to Section 24(b).',
      accept: '.pdf,.json',
      multiple_per_fy: false,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule HP',
      deduction_section: '24b',
      deduction_cap: 200_000, # for self-occupied
      tier: 4,
      ai_schema: %w[lender loan_account principal_paid interest_paid property_address possession_status period_start period_end]
    ),

    Entry.new(
      key: 'first_home_80eea',
      label: 'First-time Home Buyer Loan (80EEA)',
      short_label: '80EEA',
      category: :deduction_proof,
      description: 'Additional ₹1.5L deduction for first-time home buyers under 80EEA (subject to conditions).',
      accept: '.pdf,.json',
      multiple_per_fy: false,
      applicable_forms: %w[ITR-1 ITR-2 ITR-3 ITR-4],
      schedule: 'Schedule VI-A',
      deduction_section: '80EEA',
      deduction_cap: 150_000,
      tier: 4,
      ai_schema: %w[lender loan_account interest_paid stamp_duty_value sanction_date]
    ),

    Entry.new(
      key: 'donation_80g',
      label: 'Donation Receipt (80G)',
      short_label: '80G',
      category: :deduction_proof,
      description: 'Donations to approved charities — 50% or 100% deductible.',
      accept: '.pdf,.jpg,.jpeg,.png',
      multiple_per_fy: true,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule VI-A / Schedule 80G',
      deduction_section: '80G',
      deduction_cap: nil,
      tier: 4,
      ai_schema: %w[charity_name pan amount donation_date deduction_pct]
    ),

    Entry.new(
      key: 'rent_receipt',
      label: 'Rent Receipt / Lease Agreement',
      short_label: 'Rent',
      category: :deduction_proof,
      description: 'For HRA exemption or 80GG (when no HRA). Landlord PAN if rent > ₹1L/yr.',
      accept: '.pdf,.jpg,.jpeg,.png',
      multiple_per_fy: true,
      applicable_forms: ALL_FORMS,
      schedule: 'HRA / 80GG',
      deduction_section: 'HRA',
      deduction_cap: nil,
      tier: 4,
      ai_schema: %w[landlord landlord_pan property_address monthly_rent period_start period_end]
    ),

    # =========================================================================
    # TIER 5 — Business / professional documents (ITR-3 / ITR-4 only)
    # =========================================================================
    Entry.new(
      key: 'business_pl',
      label: 'Profit & Loss Statement',
      short_label: 'P&L',
      category: :business,
      description: 'For ITR-3 / 4 filers — business or professional income.',
      accept: '.pdf,.csv,.xlsx,.json',
      multiple_per_fy: false,
      applicable_forms: %w[ITR-3 ITR-4],
      schedule: 'Schedule P&L',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 5,
      ai_schema: %w[revenue cogs gross_profit operating_expenses depreciation net_profit]
    ),

    Entry.new(
      key: 'balance_sheet',
      label: 'Balance Sheet',
      short_label: 'BS',
      category: :business,
      description: 'For ITR-3 / 4 filers — closing balance sheet as of 31-Mar.',
      accept: '.pdf,.csv,.xlsx,.json',
      multiple_per_fy: false,
      applicable_forms: %w[ITR-3 ITR-4],
      schedule: 'Schedule BS',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 5,
      ai_schema: %w[total_assets fixed_assets current_assets total_liabilities current_liabilities equity]
    ),

    Entry.new(
      key: 'gst_summary',
      label: 'GST Summary (GSTR-1 / 3B / 9)',
      short_label: 'GST',
      category: :business,
      description: 'GST turnover for reconciliation with business income.',
      accept: '.pdf,.csv,.xlsx,.json',
      multiple_per_fy: false,
      applicable_forms: %w[ITR-3 ITR-4],
      schedule: nil,
      deduction_section: nil,
      deduction_cap: nil,
      tier: 5,
      ai_schema: %w[gstin annual_turnover taxable_turnover total_gst_paid]
    ),

    Entry.new(
      key: 'tax_audit_report',
      label: 'Tax Audit Report (Form 3CB-3CD)',
      short_label: 'Audit',
      category: :business,
      description: 'Mandatory when turnover crosses audit threshold under Section 44AB.',
      accept: '.pdf,.json',
      multiple_per_fy: false,
      applicable_forms: %w[ITR-3 ITR-4],
      schedule: nil,
      deduction_section: nil,
      deduction_cap: nil,
      tier: 5,
      ai_schema: %w[auditor_name firm_registration audit_date turnover]
    ),

    Entry.new(
      key: 'challan_tax_paid',
      label: 'Advance / Self-Assessment Tax Challan',
      short_label: 'Tax challan',
      category: :business,
      description: 'BSR / serial / date / amount for taxes paid via challan 280.',
      accept: '.pdf,.jpg,.jpeg,.png,.json',
      multiple_per_fy: true,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule IT',
      deduction_section: nil,
      deduction_cap: nil,
      tier: 5,
      ai_schema: %w[bsr_code challan_serial payment_date amount tax_head assessment_year]
    ),

    # =========================================================================
    # TIER 6 — Other / supplementary
    # =========================================================================
    Entry.new(
      key: 'form_10e',
      label: 'Form 10E (Relief u/s 89 — salary arrears)',
      short_label: 'Form 10E',
      category: :other,
      description: 'Mandatory before claiming relief on salary arrears / advance.',
      accept: '.pdf,.json',
      multiple_per_fy: false,
      applicable_forms: %w[ITR-1 ITR-2],
      schedule: nil,
      deduction_section: nil,
      deduction_cap: nil,
      tier: 6,
      ai_schema: %w[arrears_amount relief_amount nature_of_payment]
    ),

    Entry.new(
      key: 'form_12bb',
      label: 'Form 12BB (declaration to employer)',
      short_label: 'Form 12BB',
      category: :other,
      description: 'Investment declaration submitted to employer for TDS calc.',
      accept: '.pdf,.json',
      multiple_per_fy: false,
      applicable_forms: %w[ITR-1 ITR-2],
      schedule: nil,
      deduction_section: nil,
      deduction_cap: nil,
      tier: 6,
      ai_schema: %w[employer hra_claim 80c_claim 80d_claim home_loan_claim]
    ),

    Entry.new(
      key: 'form_10ba',
      label: 'Form 10BA (declaration for 80GG)',
      short_label: 'Form 10BA',
      category: :other,
      description: 'Required when claiming 80GG (rent paid without HRA).',
      accept: '.pdf,.json',
      multiple_per_fy: false,
      applicable_forms: ALL_FORMS,
      schedule: 'Schedule VI-A',
      deduction_section: '80GG',
      deduction_cap: 60_000,
      tier: 6,
      ai_schema: %w[assessee landlord property_address annual_rent]
    ),

    Entry.new(
      key: 'form_15g_15h',
      label: 'Form 15G / 15H (no-TDS declaration)',
      short_label: 'Form 15G/H',
      category: :other,
      description: 'Filed with banks to avoid TDS when income is below taxable limit.',
      accept: '.pdf,.json',
      multiple_per_fy: true,
      applicable_forms: ALL_FORMS,
      schedule: nil,
      deduction_section: nil,
      deduction_cap: nil,
      tier: 6,
      ai_schema: %w[form_type bank_name estimated_total_income]
    ),

    Entry.new(
      key: 'other',
      label: 'Other Tax Document',
      short_label: 'Other',
      category: :other,
      description: 'Anything else relevant to your filing.',
      accept: '.pdf,.csv,.xlsx,.json,.jpg,.jpeg,.png',
      multiple_per_fy: true,
      applicable_forms: ALL_FORMS,
      schedule: nil,
      deduction_section: nil,
      deduction_cap: nil,
      tier: 6,
      ai_schema: %w[notes]
    ),
  ].freeze

  BY_KEY = ENTRIES.index_by(&:key).freeze

  CATEGORIES = %i[prefill income capital_gains deduction_proof business other].freeze
  CATEGORY_LABELS = {
    prefill: 'Prefill & reconciliation',
    income: 'Income & TDS',
    capital_gains: 'Capital gains & investments',
    deduction_proof: 'Deduction proofs (Section 80)',
    business: 'Business / professional',
    other: 'Other documents',
  }.freeze

  CATEGORY_DESCRIPTIONS = {
    prefill: 'Authoritative IT-dept artifacts that auto-populate your return.',
    income: 'TDS certificates, interest, dividend and pension statements for "Other Sources".',
    capital_gains: 'Broker P&L, MF CG, depository CAS, crypto, property — for Schedule CG / VDA.',
    deduction_proof: 'Section 80C / 80D / 80CCD(1B) / 80E / 80G / 24b — only useful under the OLD regime.',
    business: 'Required for ITR-3 / ITR-4 (self-employed, freelancers, business owners).',
    other: 'Form 10E (arrears), Form 12BB, Form 15G/15H, miscellaneous.',
  }.freeze

  def self.keys
    BY_KEY.keys
  end

  def self.find(key)
    BY_KEY[key.to_s]
  end

  def self.label_for(key)
    find(key)&.label || key.to_s
  end

  def self.short_label_for(key)
    find(key)&.short_label || key.to_s
  end

  def self.category_for(key)
    find(key)&.category
  end

  def self.multiple_per_fy?(key)
    !!find(key)&.multiple_per_fy
  end

  def self.applicable_to_form?(key, form)
    entry = find(key)
    return true unless entry

    entry.applicable_forms.include?(form)
  end

  def self.ai_schema_for(key)
    find(key)&.ai_schema || []
  end

  # All deduction-proof entries grouped by section. Useful for the
  # tax-savings advisor — "how much of your 80C cap is unused".
  def self.deduction_entries_by_section
    @deduction_entries_by_section ||= ENTRIES
      .select { |e| e.deduction_section.present? }
      .group_by(&:deduction_section)
      .transform_values(&:freeze)
      .freeze
  end

  # Section caps (FY 25-26 onwards). Where multiple doc types share a
  # section the cap is the same — we read from the first.
  SECTION_CAPS = {
    '80C' => 150_000,
    '80CCD(1B)' => 50_000,
    '80D' => 100_000,
    '80DDB' => 100_000,
    '80U' => 125_000,
    '80E' => Float::INFINITY,
    '80G' => Float::INFINITY,
    '80GG' => 60_000,
    '80EEA' => 150_000,
    '24b' => 200_000,
    'HRA' => Float::INFINITY,
  }.freeze

  def self.cap_for(section)
    SECTION_CAPS[section]
  end

  def self.entries_for_category(category)
    ENTRIES.select { |e| e.category == category.to_sym }
  end

  def self.entries_for_form(form)
    ENTRIES.select { |e| e.applicable_forms.include?(form) }
  end

  # Frontend-friendly hash: { categories: [{ key, label, description,
  # entries: [{ key, label, ... }] }] }. Powers the upload screen.
  def self.frontend_catalog
    CATEGORIES.map do |cat|
      entries = entries_for_category(cat).map { |e| entry_to_h(e) }
      next if entries.empty?

      {
        key: cat,
        label: CATEGORY_LABELS[cat],
        description: CATEGORY_DESCRIPTIONS[cat],
        entries: entries,
      }
    end.compact
  end

  def self.entry_to_h(entry)
    {
      key: entry.key,
      label: entry.label,
      short_label: entry.short_label,
      category: entry.category,
      description: entry.description,
      accept: entry.accept,
      multiple_per_fy: entry.multiple_per_fy,
      applicable_forms: entry.applicable_forms,
      deduction_section: entry.deduction_section,
      deduction_cap: entry.deduction_cap == Float::INFINITY ? nil : entry.deduction_cap,
      tier: entry.tier,
    }
  end
end
