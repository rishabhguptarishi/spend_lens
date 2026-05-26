# frozen_string_literal: true

module Ai
  module Tools
    class ProposeCreateCategoryRule < Base
      def self.write_action?
        true
      end

      def self.description
        <<~DESC.strip
          Propose creating a category rule that auto-categorises future transactions whose
          description/merchant contains `pattern` to the given category. Returns a signed
          proposal token; user must click Apply.
        DESC
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            pattern: { type: 'string', description: 'Substring to match (case-insensitive), e.g. "swiggy".' },
            category_id: { type: 'integer' },
            category_name: { type: 'string' },
            reason: { type: 'string' },
          },
          required: ['pattern'],
        }
      end

      def call(args)
        pattern = args['pattern'].to_s.strip
        raise ToolError, 'pattern is required' if pattern.blank?
        raise ToolError, 'pattern too short (min 3 chars)' if pattern.length < 3

        category = resolve_category(args)
        raise ToolError, 'category_id or matching category_name is required' unless category

        token = ProposalVerifier.sign(@user, 'create_category_rule', {
          pattern: pattern,
          category_id: category.id,
        })

        {
          proposal: {
            kind: 'create_category_rule',
            token: token,
            summary: "Auto-categorise transactions matching '#{pattern}' → #{category.name}",
            reason: args['reason'].to_s[0..200],
            pattern: pattern,
            category: category.name,
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
