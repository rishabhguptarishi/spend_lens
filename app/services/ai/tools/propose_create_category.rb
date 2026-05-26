# frozen_string_literal: true

module Ai
  module Tools
    class ProposeCreateCategory < Base
      def self.write_action?
        true
      end

      def self.description
        'Propose creating a new spending category. Returns a signed proposal token.'
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            name: { type: 'string', description: 'Category name.' },
            color: { type: 'string', description: 'Hex color like #8b5cf6 (optional).' },
            reason: { type: 'string' },
          },
          required: ['name'],
        }
      end

      def call(args)
        name = args['name'].to_s.strip
        raise ToolError, 'name is required' if name.blank?
        raise ToolError, 'name too long' if name.length > 60

        if @user.categories.where('LOWER(name) = ?', name.downcase).exists?
          raise ToolError, "category '#{name}' already exists"
        end

        color = args['color'].to_s.strip
        color = nil unless color.match?(/\A#?[0-9a-fA-F]{6}\z/)

        token = ProposalVerifier.sign(@user, 'create_category', {
          name: name,
          color: color,
        })

        {
          proposal: {
            kind: 'create_category',
            token: token,
            summary: "Create category '#{name}'",
            reason: args['reason'].to_s[0..200],
            name: name,
            color: color,
          },
        }
      end
    end
  end
end
