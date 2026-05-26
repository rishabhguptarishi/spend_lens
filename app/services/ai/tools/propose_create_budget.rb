# frozen_string_literal: true

module Ai
  module Tools
    class ProposeCreateBudget < Base
      def self.write_action?
        true
      end

      def self.description
        <<~DESC.strip
          Propose creating a monthly or general budget for a category. Returns a signed
          proposal token; the user must click Apply for it to be created. Never auto-apply.
        DESC
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            category_id: { type: 'integer' },
            category_name: { type: 'string', description: 'Used if category_id missing.' },
            amount: { type: 'number', description: 'Budget amount in ₹.' },
            month: { type: 'integer', description: '1-12 for a monthly budget; omit for general.' },
            year: { type: 'integer', description: 'Year for monthly budget; omit for general.' },
            reason: { type: 'string', description: 'One-line reason shown to the user.' },
          },
          required: ['amount'],
        }
      end

      def call(args)
        amount = args['amount'].to_f
        raise ToolError, 'amount must be positive' if amount <= 0

        category = resolve_category(args)
        raise ToolError, 'category_id or category_name is required' unless category

        month = args['month'].present? ? args['month'].to_i : nil
        year = args['year'].present? ? args['year'].to_i : nil
        raise ToolError, 'month must be 1-12' if month && (month < 1 || month > 12)

        token = ProposalVerifier.sign(@user, 'create_budget', {
          category_id: category.id,
          amount: amount,
          month: month,
          year: year,
        })

        {
          proposal: {
            kind: 'create_budget',
            token: token,
            summary: "Create #{month ? "#{year}-#{format('%02d', month)} " : ''}budget of ₹#{amount.round(0)} for #{category.name}",
            reason: args['reason'].to_s[0..200],
            category: category.name,
            amount: amount,
            month: month,
            year: year,
          },
        }
      end

      private

      def resolve_category(args)
        return @user.categories.find_by(id: args['category_id']) if args['category_id'].present?

        name = args['category_name'].to_s.strip
        return nil if name.blank?

        @user.categories.find_by('LOWER(name) = ?', name.downcase)
      end
    end
  end
end
