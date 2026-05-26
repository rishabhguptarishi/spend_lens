# frozen_string_literal: true

module Ai
  module Tools
    class ItrReadiness < Base
      def self.description
        <<~DESC.strip
          Return ITR readiness for a financial year: checklist gaps, suggested form,
          income/salary/business estimates, investment summary, and document upload status.
        DESC
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            financial_year_start: { type: 'integer', description: 'Starting year of the FY, e.g. 2024 for FY 2024-25.' },
          },
        }
      end

      def call(args)
        fy = coerce_int(args['financial_year_start'], default: FinancialYear.current_start_year)
        result = ItrReadinessService.new(@user, financial_year_start: fy).call
        gaps = result[:checklist].reject { |c| c[:done] }.map { |c| c[:label] }

        # Trim the documents list to only types the user has actually
        # uploaded plus the headline singletons (Form 16, AIS, 26AS). Sending
        # all ~30 types as "{uploaded: false}" wastes tokens and clutters
        # the model's reasoning.
        relevant_docs = result[:documents].select do |k, v|
          v[:uploaded] || %w[form16 ais form26as].include?(k)
        end

        {
          financial_year: result[:financial_year_label],
          readiness_pct: result[:readiness_pct],
          suggested_form: result[:suggested_itr_form],
          income: result[:income],
          salary_estimate: result[:salary_estimate],
          business_income_estimate: result[:business_income_estimate],
          investment_summary: result[:investment_summary],
          deductions: result[:deductions],
          checklist_gaps: gaps,
          documents: relevant_docs.transform_values do |d|
            { uploaded: d[:uploaded], count: d[:count], extracted: d[:extracted] }
          end,
        }
      end
    end
  end
end
