# frozen_string_literal: true

module Ai
  module Tools
    class UncategorizedTransactions < Base
      def self.description
        <<~DESC.strip
          List the user's uncategorized debit transactions over the last N months.
          Returns up to `limit` rows. Use this before proposing a recategorize action.
        DESC
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            months_back: { type: 'integer', description: 'Look back N months (1-24). Default 3.' },
            limit: { type: 'integer', description: 'Max rows (default 25, max 100).' },
          },
        }
      end

      def call(args)
        months = coerce_int(args['months_back'], default: 3, min: 1, max: 24)
        limit = coerce_int(args['limit'], default: 25, min: 1, max: 100)
        range = months.months.ago..Time.current

        rows = user_transactions_scope(range)
          .where(transaction_type: 'debit', category_id: nil)
          .order(date: :desc)
          .limit(limit)
          .to_a

        { months_back: months, count: rows.size, transactions: rows.map { |t| serialize_txn(t) } }
      end
    end
  end
end
