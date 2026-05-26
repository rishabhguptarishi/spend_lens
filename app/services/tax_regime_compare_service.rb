# frozen_string_literal: true

# Simplified old vs new regime estimate for salaried individuals (assistive only).
class TaxRegimeCompareService
  # New regime slabs FY 2024-25+ (simplified)
  NEW_SLABS = [
    [300_000, 0],
    [600_000, 0.05],
    [900_000, 0.10],
    [1_200_000, 0.15],
    [1_500_000, 0.20],
    [Float::INFINITY, 0.30],
  ].freeze

  OLD_SLABS = [
    [250_000, 0],
    [500_000, 0.05],
    [1_000_000, 0.20],
    [Float::INFINITY, 0.30],
  ].freeze

  STANDARD_DEDUCTION_NEW = 75_000
  STANDARD_DEDUCTION_OLD = 50_000

  def initialize(user, financial_year_start:, deductions: {}, readiness: nil)
    @user = user
    @prefs = UserPreference.new(user)
    @fy = financial_year_start.to_i
    @deductions = deductions.symbolize_keys
    @readiness = readiness || ItrReadinessService.new(user, financial_year_start: @fy).call
  end

  def call
    gross = gross_income
    ded_80c = [deduction_value(:deduction_80c, 'deductions_80c'), 150_000.0].min
    ded_80d = deduction_value(:deduction_80d, 'deductions_80d')
    hra = deduction_value(:hra, 'hra_exemption')

    taxable_new = [gross - STANDARD_DEDUCTION_NEW, 0].max
    taxable_old = [gross - STANDARD_DEDUCTION_OLD - ded_80c - ded_80d - hra, 0].max

    tax_new = apply_slabs(taxable_new, NEW_SLABS)
    tax_old = apply_slabs(taxable_old, OLD_SLABS)
    cess = 0.04

    tax_new_total = (tax_new * (1 + cess)).round
    tax_old_total = (tax_old * (1 + cess)).round

    better = tax_new_total <= tax_old_total ? 'new' : 'old'

    {
      gross_income: gross.round(2),
      deductions_used: { '80c' => ded_80c, '80d' => ded_80d, 'hra' => hra },
      new_regime: {
        taxable: taxable_new.round(2),
        tax: tax_new.round(2),
        cess: (tax_new * cess).round(2),
        total: tax_new_total,
      },
      old_regime: {
        taxable: taxable_old.round(2),
        tax: tax_old.round(2),
        cess: (tax_old * cess).round(2),
        total: tax_old_total,
      },
      likely_better: better,
      user_preferred_regime: @prefs.preferred_tax_regime,
      preferred_matches_estimate: preferred_matches_estimate?(better),
      savings: (tax_old_total - tax_new_total).abs,
      disclaimer: 'Approximate calculator only. Actual tax depends on rebates, surcharge, and schedules.',
    }
  end

  private

  # Coerces a user-supplied deduction override to Float, falling back to the
  # matching Form 16 field. Empty strings, nils, and non-numeric junk all
  # collapse cleanly to 0.0 — no comparison-of-Integer-with-String crashes.
  def deduction_value(param_key, form16_key)
    raw = @deductions[param_key]
    return raw.to_f if raw.is_a?(Numeric)
    return raw.to_f if raw.is_a?(String) && !raw.strip.empty?

    form16_dig(form16_key)
  end

  def preferred_matches_estimate?(better)
    pref = @prefs.preferred_tax_regime
    return nil if pref == 'auto'

    pref == better
  end

  def gross_income
    form16_salary = form16_dig('salary')
    return form16_salary if form16_salary.positive?

    @readiness[:income].to_f
  end

  def form16_dig(key)
    doc = @user.itr_tax_documents.find_by(financial_year_start: @fy, document_type: 'form16')
    v = doc&.effective_data&.dig(key) || doc&.effective_data&.dig(key.to_s)
    v.to_f
  end

  def apply_slabs(income, slabs)
    return 0 if income <= 0

    tax = 0
    prev = 0
    slabs.each do |limit, rate|
      break if income <= prev

      chunk = [income, limit].min - prev
      tax += chunk * rate
      prev = limit
    end
    tax
  end
end
