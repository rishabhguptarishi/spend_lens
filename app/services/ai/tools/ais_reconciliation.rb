# frozen_string_literal: true

module Ai
  module Tools
    class AisReconciliation < Base
      def self.description
        'Reconcile AIS / Form 16 figures with SpendLens bank + investment data for a financial year.'
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
        result = AisReconciliationService.new(@user, financial_year_start: fy).call

        {
          financial_year: result[:financial_year_label],
          has_ais: result[:has_ais],
          has_form16: result[:has_form16],
          rows: result[:rows],
        }
      end
    end
  end
end
