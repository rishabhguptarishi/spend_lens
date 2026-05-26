# frozen_string_literal: true

# Compare AIS / Form 16 extracted figures with SpendLens bank + investment data.
class AisReconciliationService
  INTEREST_PATTERN = '(int|interest|fd|savings)'.freeze

  def initialize(user, financial_year_start:, readiness: nil)
    @user = user
    @prefs = UserPreference.new(user)
    @fy = financial_year_start.to_i
    @range = FinancialYear.range_for(@fy)
    @readiness = readiness
  end

  def call
    readiness = @readiness || ItrReadinessService.new(@user, financial_year_start: @fy).call
    ais_doc = @user.itr_tax_documents.find_by(financial_year_start: @fy, document_type: 'ais')
    form16 = @user.itr_tax_documents.find_by(financial_year_start: @fy, document_type: 'form16')
    ais_data = ais_doc&.effective_data || {}
    form16_data = form16&.effective_data || {}

    bank_interest = estimate_bank_interest
    bank_salary = readiness[:salary_estimate].to_f
    inv = readiness[:investment_summary]

    rows = [
      reconcile_row('Salary', ais_val(ais_data, form16_data, 'salary'), bank_salary, source_note(form16, ais_doc)),
      reconcile_row('Interest', ais_val(ais_data, nil, 'interest'), bank_interest, 'Bank credits tagged as interest'),
      reconcile_row('Dividends', ais_val(ais_data, nil, 'dividends'), inv[:dividends_interest].to_f, 'Portfolio + bank'),
      reconcile_row('STCG', ais_val(ais_data, nil, 'stcg'), inv[:sells].to_f * 0.5, 'Approx from sells — import broker P&L'),
      reconcile_row('LTCG', ais_val(ais_data, nil, 'ltcg'), inv[:sells].to_f * 0.5, 'Approx from sells — import broker P&L'),
      reconcile_row('TDS', ais_val(ais_data, form16_data, 'tds', 'total_tds'), 0, 'Verify in Form 26AS'),
    ]

    {
      financial_year_start: @fy,
      financial_year_label: FinancialYear.label(@fy),
      has_ais: ais_doc&.extracted?,
      has_form16: form16&.extracted?,
      rows: rows,
      gaps_count: rows.count { |r| r[:status] == 'gap' },
      match_count: rows.count { |r| r[:status] == 'match' },
    }
  end

  private

  def ais_val(ais, form16, *keys)
    keys.each do |k|
      v = ais[k] || ais[k.to_s] || form16&.dig(k) || form16&.dig(k.to_s)
      return v.to_f if v.present?
    end
    nil
  end

  def source_note(form16, ais)
    parts = []
    parts << 'Form 16' if form16&.extracted?
    parts << 'AIS' if ais&.extracted?
    parts.presence&.join(' + ') || 'Bank data only'
  end

  def estimate_bank_interest
    pattern = @prefs.description_pattern(INTEREST_PATTERN, @prefs.interest_keywords)
    Transaction.sum_credits_matching_description(
      @user.id,
      date_range: @range,
      pattern: pattern
    )
  end

  def reconcile_row(label, ais_amount, spendlens_amount, note)
    ais_amount = ais_amount.to_f if ais_amount
    spendlens = spendlens_amount.to_f
    tolerance_pct = @prefs.reconciliation_tolerance_pct / 100.0
    status = if ais_amount.nil? || ais_amount.zero?
               spendlens.positive? ? 'unverified' : 'no_data'
             elsif (ais_amount - spendlens).abs <= [ais_amount.abs * tolerance_pct, 500].max
               'match'
             else
               'gap'
             end

    {
      label: label,
      ais_amount: ais_amount,
      spendlens_amount: spendlens,
      difference: ais_amount.nil? ? nil : (ais_amount - spendlens).round(2),
      status: status,
      note: note,
    }
  end
end
