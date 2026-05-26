# frozen_string_literal: true

# Generates ranked, actionable tax-saving recommendations for the user
# based on what they've already claimed (uploaded docs) versus what's
# still available under Indian Chapter VI-A.
#
# Each recommendation reports:
#   * section ('80C')
#   * label ("80C — investments under Section 80C")
#   * cap (₹), used (₹), remaining (₹)
#   * potential_saving (₹ at the user's marginal slab rate)
#   * action (short call-to-action with concrete instruments)
#   * priority (:high / :medium / :low — drives sort order in UI)
#
# Only recommends OLD-regime deductions when the regime comparison
# suggests OLD is better (or when the user has explicitly opted into
# OLD via preferences). Under the NEW regime most Chapter VI-A
# deductions don't apply, so suggesting them would be misleading.
class TaxSavingsAdvisorService
  Recommendation = Struct.new(
    :section, :label, :cap, :used, :remaining,
    :potential_saving, :action, :priority, :reason,
    keyword_init: true
  ) do
    def to_h
      super.merge(potential_saving: potential_saving.to_i)
    end
  end

  # Marginal slab rates used to estimate potential_saving. The estimate
  # is intentionally conservative: we use the user's HIGHEST applicable
  # slab on the OLD regime since deductions reduce income at the margin.
  HIGH_SLAB = 0.30
  MID_SLAB = 0.20
  LOW_SLAB = 0.05

  def initialize(user, financial_year_start:, snapshot: nil)
    @user = user
    @fy = financial_year_start.to_i
    @snapshot = snapshot || ItrFySnapshot.new(user, financial_year_start: @fy)
    @prefs = UserPreference.new(user)
  end

  def call
    readiness = @snapshot.readiness
    regime = @snapshot.regime_compare
    income = readiness[:income].to_f
    deductions = readiness[:deductions] || {}
    suggested_form = readiness[:suggested_itr_form]

    marginal_rate = estimate_marginal_rate(income)
    old_regime_relevant = old_regime_relevant?(regime)

    recs = []

    # ----- 80C: Top-priority since it has the largest cap (₹1.5L) -----
    recs << build_80c_rec(deductions['80C'], marginal_rate) if old_regime_relevant

    # ----- 80CCD(1B): Extra ₹50k that NPS Tier-I owners often miss -----
    recs << build_80ccd1b_rec(deductions['80CCD(1B)'], marginal_rate) if old_regime_relevant

    # ----- 80D: Health insurance — cap depends on senior parents -----
    recs << build_80d_rec(deductions['80D'], marginal_rate) if old_regime_relevant

    # ----- 24b: Home loan interest, only if loan exists -----
    recs << build_24b_rec(deductions['24b'], marginal_rate) if old_regime_relevant && home_loan_indicators?

    # ----- HRA / 80GG: rent paid -----
    recs << build_rent_rec(deductions['HRA'], marginal_rate) if old_regime_relevant && rent_indicators?

    # ----- 80E / 80EEA / 80G: only nudge when there's evidence -----
    recs << build_education_loan_rec(deductions['80E'], marginal_rate) if old_regime_relevant && education_loan_indicators?
    recs << build_donation_rec(deductions['80G'], marginal_rate) if old_regime_relevant

    # ----- Universal advice (regime-agnostic) -----
    recs << build_regime_rec(regime) if regime[:savings].to_f > 1_000
    recs << build_advance_tax_rec(income) if income > 1_000_000 && !any_doc?('challan_tax_paid')

    # ----- Cross-form nudges (independent of OLD/NEW) -----
    recs << build_capital_gains_rec if needs_capital_gains_doc?

    recs.compact!
    recs.sort_by! { |r| [priority_order(r.priority), -r.potential_saving.to_f] }

    {
      financial_year_start: @fy,
      financial_year_label: FinancialYear.label(@fy),
      regime_recommendation: regime[:likely_better],
      regime_savings: regime[:savings].to_i,
      marginal_rate_used: marginal_rate,
      old_regime_relevant: old_regime_relevant,
      total_potential_saving: recs.sum { |r| r.potential_saving.to_i },
      suggested_form: suggested_form,
      recommendations: recs.map(&:to_h),
      disclaimer: 'Assistive estimates only. Actual savings depend on your full tax situation. Consult a CA before making investment decisions.',
    }
  end

  private

  def priority_order(priority)
    { high: 0, medium: 1, low: 2 }.fetch(priority, 3)
  end

  # Rough slab estimate. We use OLD-regime slabs for deduction valuation
  # since Chapter VI-A only matters under OLD.
  def estimate_marginal_rate(income)
    case income
    when 0...500_000      then 0
    when 500_000...1_000_000 then LOW_SLAB
    when 1_000_000...2_000_000 then MID_SLAB
    else HIGH_SLAB
    end
  end

  def old_regime_relevant?(regime)
    return true if @prefs.preferred_tax_regime == 'old'
    return false if @prefs.preferred_tax_regime == 'new'

    # 'auto' — show OLD-regime deductions when OLD comes out ahead OR
    # when the gap is small enough that an extra deduction could flip
    # the recommendation.
    regime[:likely_better] == 'old' || regime[:savings].to_f < 25_000
  end

  def home_loan_indicators?
    any_doc?('home_loan_cert') ||
      transaction_description_match_any?(%w[home\ loan housing\ loan lic\ hfl hdfc\ hl sbi\ hl])
  end

  def rent_indicators?
    any_doc?('rent_receipt') ||
      uploaded_lease? ||
      transaction_description_match_any?(%w[rent])
  end

  def education_loan_indicators?
    any_doc?('education_loan_80e') ||
      transaction_description_match_any?(%w[education\ loan edu\ loan credila propelld incred])
  end

  def uploaded_lease?
    @user.itr_tax_documents.for_fy(@fy).of_type('rent_receipt').exists?
  end

  def any_doc?(type)
    @user.itr_tax_documents.for_fy(@fy).of_type(type).exists?
  end

  # Postgres regex word boundaries are spelled `\y`, not `\b` (`\b` is
  # backspace under PG's POSIX engine). To keep this portable across
  # adapters we just use case-insensitive ILIKE on each token, which is
  # both faster (no regex compile) and close enough for indicator-style
  # heuristics — we only need ANY match to flip the rec on.
  def transaction_description_match_any?(tokens)
    scope = Transaction.for_user(@user.id, date_range: FinancialYear.range_for(@fy))
                       .where(transaction_type: 'debit')
    tokens.any? do |token|
      scope.where('description ILIKE ?', "%#{token.tr('\\', '')}%").exists?
    end
  rescue ActiveRecord::StatementInvalid
    false
  end

  def needs_capital_gains_doc?
    inv = @snapshot.readiness[:investment_summary]
    return false unless inv[:has_capital_gains_events]

    !any_doc?('broker_pl') && !any_doc?('mf_cg')
  end

  # ============================================================================
  # Individual recommendation builders
  # ============================================================================
  def build_80c_rec(section_data, marginal_rate)
    cap = 150_000
    used = section_data&.dig(:used).to_f
    remaining = [cap - used, 0].max
    saving = (remaining * marginal_rate).round
    priority = remaining > 100_000 ? :high : (remaining > 25_000 ? :medium : :low)
    Recommendation.new(
      section: '80C',
      label: 'Section 80C — investments cap',
      cap: cap,
      used: used.round(2),
      remaining: remaining.round(2),
      potential_saving: saving,
      priority: priority,
      action: action_for_80c(remaining),
      reason: "₹#{cap.to_i} cap, ₹#{used.to_i} claimed via uploaded receipts."
    )
  end

  def action_for_80c(remaining)
    return 'Cap utilised — no further 80C contribution will reduce tax.' if remaining.zero?

    options = [
      "ELSS mutual fund (3-yr lock-in, equity returns)",
      "PPF (15-yr lock-in, sovereign 7.1%)",
      "Sukanya Samriddhi (if you have a daughter <10)",
      "NSC (5-yr lock-in, 7.7%)",
      "Children's tuition fees (already paid this FY?)",
    ]
    "Invest up to ₹#{remaining.to_i} more before 31-Mar. Options: #{options.first(3).join(' / ')}."
  end

  def build_80ccd1b_rec(section_data, marginal_rate)
    cap = 50_000
    used = section_data&.dig(:used).to_f
    remaining = [cap - used, 0].max
    saving = (remaining * marginal_rate).round
    priority = remaining > 30_000 ? :high : :medium
    Recommendation.new(
      section: '80CCD(1B)',
      label: 'Section 80CCD(1B) — extra NPS Tier-I',
      cap: cap,
      used: used.round(2),
      remaining: remaining.round(2),
      potential_saving: saving,
      priority: priority,
      action: remaining.positive? ? "Open or top-up NPS Tier-I with ₹#{remaining.to_i} for an additional deduction OVER AND ABOVE the 80C cap." : 'Maxed out.',
      reason: '80CCD(1B) is a separate ₹50,000 deduction exclusive to NPS Tier-I — most filers miss it.'
    )
  end

  def build_80d_rec(section_data, marginal_rate)
    cap = 100_000
    used = section_data&.dig(:used).to_f
    remaining = [cap - used, 0].max
    saving = (remaining * marginal_rate).round
    priority = used.zero? ? :high : :low
    Recommendation.new(
      section: '80D',
      label: 'Section 80D — health insurance premium',
      cap: cap,
      used: used.round(2),
      remaining: remaining.round(2),
      potential_saving: saving,
      priority: priority,
      action: used.zero? ? 'Buy or upload an existing health insurance premium receipt — ₹25k self/spouse/kids + ₹50k senior parents.' : "Top-up by ₹#{remaining.to_i} if you have senior parents you can cover.",
      reason: 'Premium for self+family (₹25k) + senior parents (₹50k) + preventive health check (₹5k within cap).'
    )
  end

  def build_24b_rec(section_data, marginal_rate)
    cap = 200_000
    used = section_data&.dig(:used).to_f
    remaining = [cap - used, 0].max
    saving = (remaining * marginal_rate).round
    Recommendation.new(
      section: '24b',
      label: 'Section 24(b) — home loan interest',
      cap: cap,
      used: used.round(2),
      remaining: remaining.round(2),
      potential_saving: saving,
      priority: used.zero? ? :high : :medium,
      action: any_doc?('home_loan_cert') ? "Verify your lender certificate shows interest paid (max ₹#{cap.to_i}/year for self-occupied)." : 'Upload your bank-issued home loan certificate to claim interest under Section 24(b).',
      reason: 'For self-occupied property; max ₹2L/yr.'
    )
  end

  def build_rent_rec(_section_data, marginal_rate)
    # No flat cap — value comes from claiming HRA exemption in salary
    # or 80GG (₹60k/year) if no HRA component.
    has_hra_in_form16 = form16_has_hra?
    if has_hra_in_form16
      Recommendation.new(
        section: 'HRA',
        label: 'House Rent Allowance (HRA exemption)',
        cap: nil,
        used: 0,
        remaining: nil,
        potential_saving: (30_000 * marginal_rate).round, # rough placeholder
        priority: any_doc?('rent_receipt') ? :low : :medium,
        action: any_doc?('rent_receipt') ? 'Rent receipts uploaded — make sure landlord PAN is included if annual rent > ₹1L.' : 'Upload rent receipts for the FY to support HRA exemption claimed in Form 16.',
        reason: 'HRA exemption is the LOWER of (a) actual HRA received, (b) rent paid minus 10% of basic, (c) 50% / 40% of basic (metro / non-metro).'
      )
    else
      Recommendation.new(
        section: '80GG',
        label: 'Section 80GG — rent without HRA',
        cap: 60_000,
        used: 0,
        remaining: 60_000,
        potential_saving: (60_000 * marginal_rate).round,
        priority: :medium,
        action: 'No HRA in your salary structure — file Form 10BA and claim Section 80GG (max ₹60,000/yr).',
        reason: '80GG kicks in only when there\'s no HRA. Requires Form 10BA declaration.'
      )
    end
  end

  def form16_has_hra?
    docs = @user.itr_tax_documents.for_fy(@fy).of_type('form16')
    docs.any? { |d| d.effective_data&.dig('hra_received').to_f.positive? || d.effective_data&.dig('hra_exemption').to_f.positive? }
  end

  def build_education_loan_rec(section_data, marginal_rate)
    used = section_data&.dig(:used).to_f
    Recommendation.new(
      section: '80E',
      label: 'Section 80E — education loan interest (no upper cap)',
      cap: nil,
      used: used.round(2),
      remaining: nil,
      potential_saving: used.zero? ? (50_000 * marginal_rate).round : 0,
      priority: used.zero? ? :medium : :low,
      action: used.zero? ? 'Upload your education-loan interest certificate — 100% of interest is deductible (no cap), up to 8 years from when repayment started.' : 'Already claiming education loan interest — continue until 8-year limit.',
      reason: '80E has NO upper cap and continues for 8 years from the start of repayment.'
    )
  end

  def build_donation_rec(section_data, marginal_rate)
    used = section_data&.dig(:used).to_f
    return nil if used > 5_000 # don't nudge people already donating

    Recommendation.new(
      section: '80G',
      label: 'Section 80G — donations to approved charities',
      cap: nil,
      used: used.round(2),
      remaining: nil,
      potential_saving: (10_000 * marginal_rate).round,
      priority: :low,
      action: 'If you donated to PM CARES, Red Cross, or any 80G-approved charity, upload the receipt to claim 50%/100% deduction.',
      reason: 'Smaller savings, but worth claiming when receipts already exist.'
    )
  end

  def build_regime_rec(regime)
    better = regime[:likely_better]
    saving = regime[:savings].to_i
    other = better == 'new' ? 'OLD' : 'NEW'
    Recommendation.new(
      section: 'REGIME',
      label: "Choose the #{better.upcase} regime this year",
      cap: nil,
      used: 0,
      remaining: nil,
      potential_saving: saving,
      priority: saving > 10_000 ? :high : :medium,
      action: "Our slab calculator shows the #{better.upcase} regime saves ₹#{saving} vs #{other} for your income profile. Toggle the regime when filing.",
      reason: 'Regime choice is the single biggest lever each year — re-evaluate annually.'
    )
  end

  def build_advance_tax_rec(income)
    Recommendation.new(
      section: 'ADVANCE_TAX',
      label: 'Pay advance tax (Section 234B/C interest)',
      cap: nil,
      used: 0,
      remaining: nil,
      potential_saving: (income * 0.001).round, # avoided interest, rough estimate
      priority: :medium,
      action: 'Income > ₹10L? Pay advance tax in 4 instalments (15-Jun, 15-Sep, 15-Dec, 15-Mar) to avoid 234B/C interest.',
      reason: 'Advance tax becomes mandatory once total tax liability exceeds ₹10,000. Missing instalments triggers 1%/month interest.'
    )
  end

  def build_capital_gains_rec
    Recommendation.new(
      section: 'CG_DOCS',
      label: 'Upload broker P&L or MF capital gains statement',
      cap: nil,
      used: 0,
      remaining: nil,
      potential_saving: 0,
      priority: :high,
      action: 'You have realized capital gains this FY but no broker/MF tax report uploaded. ITR-2 / 3 requires Schedule CG — without docs you cannot file correctly.',
      reason: 'Filing without CG documentation risks notices and refund delays.'
    )
  end
end
