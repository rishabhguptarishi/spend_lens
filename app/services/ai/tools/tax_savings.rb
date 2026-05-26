# frozen_string_literal: true

module Ai
  module Tools
    # Surfaces TaxSavingsAdvisorService output to the LLM. The agent can
    # ask "how can I save more tax?" and get a ranked list with concrete
    # dollar figures and call-to-action strings.
    class TaxSavings < Base
      def self.description
        <<~DESC.strip
          Return ranked, actionable tax-saving recommendations for a financial year:
          unused 80C / 80D / 80CCD(1B) caps, HRA vs 80GG, home loan, education loan,
          regime choice, and capital-gains documentation gaps. Includes potential
          rupee savings at the user's estimated marginal slab rate.
        DESC
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            financial_year_start: { type: 'integer', description: 'Starting year of the FY, e.g. 2025 for FY 2025-26.' },
          },
        }
      end

      def call(args)
        fy = coerce_int(args['financial_year_start'], default: FinancialYear.current_start_year)
        result = TaxSavingsAdvisorService.new(@user, financial_year_start: fy).call

        # Trim down to what the LLM actually needs to reason — full
        # action strings are tens of tokens each so we keep them, but
        # drop the raw disclaimer (we add it back in the system prompt).
        {
          financial_year: result[:financial_year_label],
          regime_recommendation: result[:regime_recommendation],
          regime_savings: result[:regime_savings],
          marginal_rate_used: result[:marginal_rate_used],
          old_regime_relevant: result[:old_regime_relevant],
          total_potential_saving: result[:total_potential_saving],
          recommendations: result[:recommendations],
        }
      end
    end
  end
end
