# frozen_string_literal: true

module Ai
  module Tools
    class BudgetStatus < Base
      def self.description
        <<~DESC.strip
          Return the user's budgets with month-to-date spend and remaining amounts for
          the requested month. Defaults to the current month.
        DESC
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            month: { type: 'integer', description: '1-12. Defaults to current month.' },
            year: { type: 'integer', description: 'Defaults to current year.' },
          },
        }
      end

      def call(args)
        today = Date.current
        month = coerce_int(args['month'], default: today.month, min: 1, max: 12)
        year = coerce_int(args['year'], default: today.year, min: 2000, max: today.year + 1)

        rows = @user.budgets.includes(:category).map do |b|
          spent = b.spent_in_period(month: month, year: year)
          {
            category: b.category&.name,
            budget: b.amount.to_f,
            spent: spent.round(2),
            remaining: (b.amount.to_f - spent).round(2),
            usage_pct: b.amount.to_f.positive? ? ((spent / b.amount.to_f) * 100).round(1) : nil,
            period: b.month && b.year ? "#{b.year}-#{format('%02d', b.month)}" : 'general',
          }
        end

        { month: month, year: year, budgets: rows }
      end
    end
  end
end
