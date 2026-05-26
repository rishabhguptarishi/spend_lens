# frozen_string_literal: true

module Ai
  # Executes a previously-signed proposal after the user clicks Apply.
  # Re-validates ownership before mutating.
  class ProposalExecutor
    class ExecutionError < StandardError; end

    def initialize(user)
      @user = user
    end

    def call(token)
      payload = ProposalVerifier.verify(token, user: @user)
      send("apply_#{payload[:kind]}", payload[:args])
    end

    private

    def apply_recategorize_transactions(args)
      ids = Array(args[:transaction_ids]).map(&:to_i)
      raise ExecutionError, 'no transaction ids' if ids.empty?

      create_payload = args[:create_category].respond_to?(:with_indifferent_access) ? args[:create_category].with_indifferent_access : nil

      category = if args[:category_id].present?
                   @user.categories.find_by(id: args[:category_id])
                 elsif create_payload.present?
                   @user.categories.find_or_create_by!(name: create_payload[:name].to_s.strip)
                 end
      raise ExecutionError, 'target category not found' unless category

      affected = Transaction
        .joins(statement: :bank_account)
        .where(bank_accounts: { user_id: @user.id }, id: ids)

      count = 0
      Transaction.transaction do
        affected.find_each { |t| t.update!(category: category); count += 1 }
      end

      { kind: 'recategorize_transactions', updated_count: count, category: category.name }
    end

    def apply_create_budget(args)
      raise ExecutionError, 'category_id missing' unless args[:category_id]

      category = @user.categories.find_by(id: args[:category_id])
      raise ExecutionError, 'category not found' unless category

      budget = @user.budgets.create!(
        category: category,
        amount: args[:amount].to_f,
        month: args[:month].presence,
        year: args[:year].presence
      )

      { kind: 'create_budget', budget_id: budget.id, category: category.name, amount: budget.amount.to_f }
    end

    def apply_create_category_rule(args)
      category = @user.categories.find_by(id: args[:category_id])
      raise ExecutionError, 'category not found' unless category

      rule = @user.category_rules.create!(
        category: category,
        merchant_pattern: args[:pattern].to_s.strip
      )

      { kind: 'create_category_rule', rule_id: rule.id, pattern: rule.merchant_pattern, category: category.name }
    end

    def apply_create_category(args)
      name = args[:name].to_s.strip
      raise ExecutionError, 'name required' if name.blank?

      if @user.categories.where('LOWER(name) = ?', name.downcase).exists?
        raise ExecutionError, "category '#{name}' already exists"
      end

      attrs = { name: name }
      attrs[:color] = args[:color] if args[:color].present?
      category = @user.categories.create!(attrs)

      { kind: 'create_category', category_id: category.id, name: category.name }
    end
  end
end
