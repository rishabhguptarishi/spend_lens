# frozen_string_literal: true

# Memoized FY aggregates — build once per request/job.
class ItrFySnapshot
  attr_reader :user, :fy, :range

  def initialize(user, financial_year_start:)
    @user = user
    @fy = financial_year_start.to_i
    @range = FinancialYear.range_for(@fy)
  end

  def readiness
    @readiness ||= ItrReadinessService.new(user, financial_year_start: fy).call
  end

  def reconciliation
    @reconciliation ||= AisReconciliationService.new(user, financial_year_start: fy, readiness: readiness).call
  end

  def regime_compare(deductions: {})
    @regime_compare ||= TaxRegimeCompareService.new(
      user,
      financial_year_start: fy,
      deductions: deductions,
      readiness: readiness
    ).call
  end

  def capital_gains
    @capital_gains ||= CapitalGainsSummaryService.new(user, financial_year_start: fy).call
  end

  def tax_savings
    @tax_savings ||= TaxSavingsAdvisorService.new(user, financial_year_start: fy, snapshot: self).call
  end
end
