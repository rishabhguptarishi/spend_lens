# frozen_string_literal: true

module Ai
  module Tools
    class HoldingsSnapshot < Base
      def self.description
        'Return the user\'s current investment holdings (units, market value, gain/loss).'
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            limit: { type: 'integer', description: 'Max holdings to return (default 50, max 200).' },
          },
        }
      end

      def call(args)
        limit = coerce_int(args['limit'], default: 50, min: 1, max: 200)
        rows = @user.investment_holdings
                    .includes(:investment_account)
                    .order(invested_amount: :desc)
                    .limit(limit)
                    .map do |h|
          {
            symbol: h.symbol,
            folio: h.folio,
            units: h.units.to_f,
            avg_cost: h.avg_cost.to_f,
            invested_amount: h.invested_amount.to_f,
            account: h.investment_account&.name,
            account_kind: h.investment_account&.account_kind,
          }
        end
        total_invested = rows.sum { |r| r[:invested_amount] }
        { count: rows.size, total_invested: total_invested.round(2), holdings: rows }
      end
    end
  end
end
