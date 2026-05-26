# frozen_string_literal: true

module Ai
  module Tools
    class CapitalGains < Base
      def self.description
        'Summarise short-term and long-term capital gains for a financial year, with per-holding rows.'
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            financial_year_start: { type: 'integer', description: 'FY start year (e.g. 2024 for FY 2024-25).' },
            limit: { type: 'integer', description: 'Max rows to return (default 50, max 200).' },
          },
        }
      end

      def call(args)
        fy = coerce_int(args['financial_year_start'], default: FinancialYear.current_start_year)
        limit = coerce_int(args['limit'], default: 50, min: 1, max: 200)
        result = CapitalGainsSummaryService.new(@user, financial_year_start: fy).call

        {
          financial_year: FinancialYear.label(fy),
          document_stcg: result[:document_stcg],
          document_ltcg: result[:document_ltcg],
          total_rows: result[:rows].size,
          rows: result[:rows].first(limit),
        }
      end
    end
  end
end
