# frozen_string_literal: true

module Ai
  module Tools
    class RecurringTransactions < Base
      def self.description
        'List the user\'s detected recurring transactions (SIPs, EMIs, subscriptions).'
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            months_back: { type: 'integer', description: 'Look back N months (1-24). Default 6.' },
            limit: { type: 'integer', description: 'Max rows (default 25, max 50).' },
          },
        }
      end

      def call(args)
        months = coerce_int(args['months_back'], default: 6, min: 1, max: 24)
        limit = coerce_int(args['limit'], default: 25, min: 1, max: 50)
        range = months.months.ago..Time.current

        rows = user_transactions_scope(range)
          .where(is_recurring: true)
          .order(date: :desc)
          .limit(limit)
          .to_a

        { months_back: months, count: rows.size, recurring: rows.map { |t| serialize_txn(t) } }
      end
    end
  end
end
