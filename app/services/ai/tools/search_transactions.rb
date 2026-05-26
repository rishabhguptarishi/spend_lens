# frozen_string_literal: true

module Ai
  module Tools
    class SearchTransactions < Base
      MAX_LIMIT = 100

      def self.description
        <<~DESC.strip
          Search the user's bank transactions by keyword (merchant or description),
          optionally filtered by transaction type, date range, or amount.
          Returns up to `limit` matching rows. Use this instead of guessing — always
          search before quoting specific transactions.
        DESC
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            query: { type: 'string', description: 'Keyword(s) to match in description/merchant/category.' },
            months_back: { type: 'integer', description: 'Look back N months from today (1-24). Default 6.' },
            type: { type: 'string', enum: %w[debit credit any], description: 'Filter by debit, credit, or any.' },
            min_amount: { type: 'number', description: 'Minimum absolute amount in ₹.' },
            max_amount: { type: 'number', description: 'Maximum absolute amount in ₹.' },
            limit: { type: 'integer', description: 'Max rows to return (default 25, hard cap 100).' },
          },
          required: ['query'],
        }
      end

      def call(args)
        query = coerce_str(args['query'])
        raise ToolError, 'query is required' if query.blank?

        type = coerce_str(args['type'], allowed: %w[debit credit any], default: 'any')
        limit = coerce_int(args['limit'], default: 25, min: 1, max: MAX_LIMIT)
        range = month_range(args['months_back'])

        scope = user_transactions_scope(range).left_joins(:category)
        scope = scope.where(transaction_type: type) if type != 'any'
        scope = scope.where('transactions.amount >= ?', args['min_amount'].to_f) if args['min_amount'].present?
        scope = scope.where('transactions.amount <= ?', args['max_amount'].to_f) if args['max_amount'].present?

        pattern = "%#{query.downcase}%"
        scope = scope.where(
          "LOWER(transactions.description) LIKE ? OR LOWER(COALESCE(transactions.merchant,'')) LIKE ? OR LOWER(COALESCE(categories.name,'')) LIKE ?",
          pattern, pattern, pattern
        )

        rows = scope.distinct.order(date: :desc).limit(limit).to_a
        total = scope.distinct.count

        {
          query: query,
          months_back: range.begin.then { |b| ((Time.current - b) / 1.month).round },
          matched_count: total,
          returned: rows.size,
          transactions: rows.map { |t| serialize_txn(t) },
        }
      end
    end
  end
end
