# frozen_string_literal: true

module Ai
  module Tools
    class ListCategories < Base
      def self.description
        'List all of the user\'s spending categories (id, name, color).'
      end

      def self.parameters_schema
        { type: 'object', properties: {} }
      end

      def call(_args)
        cats = @user.categories.order(:name).map do |c|
          { id: c.id, name: c.name, color: c.color }
        end
        { count: cats.size, categories: cats }
      end
    end
  end
end
