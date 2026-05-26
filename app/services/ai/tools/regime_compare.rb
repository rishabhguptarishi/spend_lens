# frozen_string_literal: true

module Ai
  module Tools
    class RegimeCompare < Base
      def self.description
        'Compare old vs new tax regime for the user for a financial year.'
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            financial_year_start: { type: 'integer', description: 'FY start year (e.g. 2024 for FY 2024-25).' },
          },
        }
      end

      def call(args)
        fy = coerce_int(args['financial_year_start'], default: FinancialYear.current_start_year)
        result = TaxRegimeCompareService.new(@user, financial_year_start: fy).call

        {
          financial_year: FinancialYear.label(fy),
          old_regime: result[:old_regime],
          new_regime: result[:new_regime],
          likely_better: result[:likely_better],
          difference: result[:difference],
        }
      end
    end
  end
end
