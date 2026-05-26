# frozen_string_literal: true

module BankTransactionScopes
  extend ActiveSupport::Concern

  def self.combined_description_pattern(base_pattern, extra_keywords)
    extras = Array(extra_keywords).map(&:to_s).map(&:strip).reject(&:blank?).map { |k| Regexp.escape(k) }
    return base_pattern if extras.empty?

    inner = base_pattern.to_s.delete_prefix('(').delete_suffix(')')
    "(#{inner}|#{extras.join('|')})"
  end

  class_methods do
    def for_user(user_id, date_range:)
      joins(statement: :bank_account)
        .where(bank_accounts: { user_id: user_id })
        .where(date: date_range)
    end

    def sum_credits_matching_description(user_id, date_range:, pattern:)
      for_user(user_id, date_range: date_range)
        .where(transaction_type: 'credit')
        .where('transactions.description ~* ?', pattern)
        .sum(:amount)
        .to_f
    end

    def combined_description_pattern(base_pattern, extra_keywords)
      BankTransactionScopes.combined_description_pattern(base_pattern, extra_keywords)
    end
  end
end
