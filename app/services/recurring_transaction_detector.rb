# frozen_string_literal: true

# Detects likely recurring/subscription transactions from history.
class RecurringTransactionDetector
  RECURRING_KEYWORDS = %w[
    netflix spotify amazon prime youtube premium disney hotstar
    subscription recurring monthly annual membership
  ].freeze

  def initialize(user)
    @user = user
  end

  def recurring?(description, amount, date)
    return false if description.blank?

    desc = description.to_s.downcase
    return true if RECURRING_KEYWORDS.any? { |kw| desc.include?(kw) }

    # Same merchant + similar amount in the 4 months *before* this transaction
    # = likely recurring. Window must be anchored to the transaction's own date,
    # not Time.current, otherwise statements from past months/years would always
    # produce an empty window (lower bound > upper bound) and never detect any
    # recurring activity.
    return false unless date.is_a?(Date)

    similar = Transaction
      .joins(statement: :bank_account)
      .where(bank_accounts: { user_id: @user.id })
      .where('transactions.date >= ?', date - 4.months)
      .where('transactions.date < ?', date)
      .where('LOWER(transactions.description) LIKE ?', "%#{extract_merchant(desc)}%")
      .where('ABS(transactions.amount - ?) < ?', amount.to_f, amount.to_f * 0.05)

    similar.count >= 2
  end

  private

  def extract_merchant(desc)
    words = desc.split(/\s+/).reject { |w| w.length < 3 }
    words.find { |w| w.length >= 4 } || words.first || ''
  end
end
