# frozen_string_literal: true

module Ai
  module Tools
    class BestCardForPurchase < Base
      def self.description
        <<~DESC.strip
          Recommend the best credit card for a single purchase given a category and/or
          merchant and amount. Uses the user's card reward structures.
        DESC
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            category: { type: 'string', description: 'Spend category (e.g. "Dining", "Travel").' },
            merchant: { type: 'string', description: 'Merchant name (used to infer category if category missing).' },
            amount: { type: 'number', description: 'Purchase amount in ₹.' },
          },
        }
      end

      def call(args)
        result = BestCardForPurchaseService.new(@user).call(
          category: args['category'],
          merchant: args['merchant'],
          amount: args['amount']
        )
        result
      end
    end
  end
end
