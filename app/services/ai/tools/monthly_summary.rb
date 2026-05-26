# frozen_string_literal: true

module Ai
  module Tools
    class MonthlySummary < Base
      def self.description
        <<~DESC.strip
          Summarise income vs expenses, net cash flow, and top categories for the user
          over the last N months. Use this for "how did I spend last month" type questions.
        DESC
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            months_back: { type: 'integer', description: 'Number of months to summarise (1-24). Default 1.' },
          },
        }
      end

      def call(args)
        months = coerce_int(args['months_back'], default: 1, min: 1, max: 24)
        range = months.months.ago..Time.current
        scope = user_transactions_scope(range)

        income = scope.where(transaction_type: 'credit').sum(:amount).to_f.round(2)
        expense = scope.where(transaction_type: 'debit').sum(:amount).to_f.round(2)

        by_month = scope.group("date_trunc('month', date)").group(:transaction_type).sum(:amount)
        months_breakdown = by_month.each_with_object({}) do |((month, type), amount), acc|
          key = month.strftime('%Y-%m')
          acc[key] ||= { income: 0.0, expense: 0.0 }
          acc[key][type == 'credit' ? :income : :expense] = amount.to_f.round(2)
        end

        top_categories = scope
          .where(transaction_type: 'debit')
          .left_joins(:category)
          .group('categories.name')
          .order('sum_amount DESC')
          .limit(10)
          .sum(:amount)
          .map { |name, amt| { category: name || 'Uncategorized', total: amt.to_f.round(2) } }

        {
          period_months: months,
          income: income,
          expense: expense,
          net: (income - expense).round(2),
          monthly_breakdown: months_breakdown.sort.to_h,
          top_categories: top_categories,
        }
      end
    end
  end
end
