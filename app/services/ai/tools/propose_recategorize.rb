# frozen_string_literal: true

module Ai
  module Tools
    # Returns a signed proposal that the user must explicitly confirm.
    # Never mutates state itself.
    class ProposeRecategorize < Base
      def self.write_action?
        true
      end

      def self.description
        <<~DESC.strip
          Propose recategorising a set of transactions to a given category.
          Always look up the category name in `list_categories` first (or use
          category_name to create one only if the user agreed). Returns a
          signed proposal token; the user must click Apply for the change to take effect.
          Never auto-apply changes.
        DESC
      end

      def self.parameters_schema
        {
          type: 'object',
          properties: {
            transaction_ids: {
              type: 'array',
              items: { type: 'integer' },
              description: 'IDs of the transactions to recategorise.',
            },
            category_id: { type: 'integer', description: 'Existing category id.' },
            category_name: {
              type: 'string',
              description: 'Category name. Used to look up existing or (if create_if_missing) propose creation.',
            },
            create_if_missing: {
              type: 'boolean',
              description: 'If true and category_name does not exist, the proposal also creates it on apply.',
            },
            reason: { type: 'string', description: 'One-line human reason shown to the user.' },
          },
          required: ['transaction_ids'],
        }
      end

      def call(args)
        ids = Array(args['transaction_ids']).map(&:to_i).reject(&:zero?).uniq
        raise ToolError, 'transaction_ids is required' if ids.empty?
        raise ToolError, 'too many transactions (max 200)' if ids.size > 200

        owned_ids = Transaction
          .joins(statement: :bank_account)
          .where(bank_accounts: { user_id: @user.id }, id: ids)
          .pluck(:id)
        raise ToolError, 'no matching transactions for this user' if owned_ids.empty?

        category, create_payload = resolve_category(args)

        sample = Transaction.where(id: owned_ids).limit(8).pluck(:date, :description, :amount, :transaction_type).map do |d, desc, amt, t|
          { date: d&.strftime('%Y-%m-%d'), description: desc.to_s[0..80], amount: amt.to_f, type: t }
        end

        token = ProposalVerifier.sign(@user, 'recategorize_transactions', {
          transaction_ids: owned_ids,
          category_id: category&.id,
          create_category: create_payload,
        })

        {
          proposal: {
            kind: 'recategorize_transactions',
            token: token,
            summary: "Recategorise #{owned_ids.size} transaction(s) → #{category&.name || create_payload&.dig(:name)}",
            reason: args['reason'].to_s[0..200],
            transaction_count: owned_ids.size,
            sample_transactions: sample,
            target_category: category&.name || create_payload&.dig(:name),
            creates_new_category: create_payload.present?,
          },
        }
      end

      private

      def resolve_category(args)
        if args['category_id'].present?
          cat = @user.categories.find_by(id: args['category_id'])
          raise ToolError, "category id #{args['category_id']} not found" unless cat

          return [cat, nil]
        end

        name = args['category_name'].to_s.strip
        raise ToolError, 'category_id or category_name is required' if name.blank?

        existing = @user.categories.find_by('LOWER(name) = ?', name.downcase)
        return [existing, nil] if existing

        unless args['create_if_missing']
          raise ToolError, "category '#{name}' not found. Set create_if_missing=true to propose creation."
        end

        [nil, { name: name }]
      end
    end
  end
end
