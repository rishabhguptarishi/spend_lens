# frozen_string_literal: true

module Ai
  module Tools
    class NetWorth < Base
      def self.description
        'Return the user\'s current net worth snapshot: bank balances + investments - credit dues.'
      end

      def self.parameters_schema
        { type: 'object', properties: {} }
      end

      def call(_args)
        NetWorthService.new(@user).call
      end
    end
  end
end
