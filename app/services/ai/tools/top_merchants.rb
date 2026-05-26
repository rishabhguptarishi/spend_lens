# frozen_string_literal: true

module Ai
  module Tools
    class TopMerchants < Base
      def self.description
        'Return the top merchants by total debit amount over N months.'
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            months_back: { type: 'integer', description: 'Look back N months (1-24). Default 3.' },
            limit: { type: 'integer', description: 'Max merchants to return (default 10, max 25).' },
          },
        }
      end

      def call(args)
        months = coerce_int(args['months_back'], default: 3, min: 1, max: 24)
        limit = coerce_int(args['limit'], default: 10, min: 1, max: 25)
        range = months.months.ago..Time.current
        scope = user_transactions_scope(range).where(transaction_type: 'debit')

        merchants = scope.group(:merchant, :description).sum(:amount)
        rolled = merchants.each_with_object({}) do |((m, d), amt), acc|
          key = (m.presence || d.to_s).to_s.strip[0..80]
          next if key.blank?

          acc[key] = (acc[key] || 0) + amt.to_f
        end

        top = rolled.sort_by { |_, v| -v }.first(limit).map { |name, amt| { merchant: name, total: amt.round(2) } }
        { months_back: months, top_merchants: top }
      end
    end
  end
end
