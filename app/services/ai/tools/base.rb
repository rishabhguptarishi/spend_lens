# frozen_string_literal: true

module Ai
  module Tools
    # Base class for an agent tool. Subclasses implement:
    #   self.tool_name           → snake_case name exposed to the LLM
    #   self.description         → plain-text description the LLM reads
    #   self.parameters_schema   → JSON schema {type, properties, required}
    #   #call(args)              → returns a Hash (will be JSON-serialised)
    #
    # Read tools just return data. Write tools never mutate; they return a
    # `:proposal` payload that the user must confirm via the apply endpoint.
    class Base
      class ToolError < StandardError; end

      def self.tool_name
        name.demodulize.underscore
      end

      def self.description
        raise NotImplementedError
      end

      def self.parameters_schema
        { type: 'object', properties: {}, required: [] }
      end

      def self.write_action?
        false
      end

      def self.declaration
        {
          name: tool_name,
          description: description,
          parameters: parameters_schema,
        }
      end

      def initialize(user)
        @user = user
        @prefs = UserPreference.new(user)
      end

      def call(_args)
        raise NotImplementedError
      end

      protected

      def coerce_int(value, default: nil, min: nil, max: nil)
        v = value.to_s.strip
        return default if v.empty?

        n = v.to_i
        n = min if min && n < min
        n = max if max && n > max
        n
      end

      def coerce_str(value, allowed: nil, default: nil)
        v = value.to_s.strip
        return default if v.empty?
        return default if allowed && !allowed.include?(v)

        v
      end

      def month_range(months_back)
        n = coerce_int(months_back, default: @prefs.ai_context_months, min: 1, max: 24)
        n.months.ago..Time.current
      end

      def user_transactions_scope(range)
        Transaction
          .joins(statement: :bank_account)
          .includes(:category, statement: :bank_account)
          .where(bank_accounts: { user_id: @user.id })
          .where(date: range)
      end

      def serialize_txn(t)
        {
          id: t.id,
          date: t.date&.strftime('%Y-%m-%d'),
          description: t.description.to_s[0..160],
          amount: t.amount.to_f,
          type: t.transaction_type,
          category: t.category&.name,
          account: t.statement&.bank_account&.name,
        }
      end
    end
  end
end
