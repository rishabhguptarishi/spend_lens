# frozen_string_literal: true

class AiItrContextService
  def initialize(user, financial_year_start: nil, question: nil)
    @user = user
    @fy = (financial_year_start || FinancialYear.current_start_year).to_i
    @question = question
    @snapshot = ItrFySnapshot.new(user, financial_year_start: @fy)
  end

  def call
    readiness = @snapshot.readiness
    reconciliation = @snapshot.reconciliation
    regime = @snapshot.regime_compare
    cg = @snapshot.capital_gains
    savings = @snapshot.tax_savings

    {
      financial_year: FinancialYear.label(@fy),
      readiness_pct: readiness[:readiness_pct],
      checklist_gaps: readiness[:checklist].reject { |c| c[:done] }.map { |c| c[:label] },
      suggested_form: readiness[:suggested_itr_form],
      income: readiness[:income],
      salary_estimate: readiness[:salary_estimate],
      business_income_estimate: readiness[:business_income_estimate],
      investment_summary: readiness[:investment_summary],
      deductions: readiness[:deductions],
      reconciliation_gaps: reconciliation[:rows].select { |r| r[:status] == 'gap' },
      regime_comparison: {
        new_total: regime.dig(:new_regime, :total),
        old_total: regime.dig(:old_regime, :total),
        likely_better: regime[:likely_better],
        savings: regime[:savings],
      },
      capital_gains_count: cg[:rows].size,
      document_stcg: cg[:document_stcg],
      document_ltcg: cg[:document_ltcg],
      documents_uploaded: readiness[:documents].select { |_, d| d[:uploaded] }.keys,
      # Compact savings advisor digest — top 5 recs only to keep prompt size
      # reasonable. The agentic chat has the full tool access if needed.
      tax_savings: {
        total_potential_saving: savings[:total_potential_saving],
        regime_recommendation: savings[:regime_recommendation],
        top_recommendations: savings[:recommendations]&.first(5),
      },
      question: @question,
    }
  end
end
