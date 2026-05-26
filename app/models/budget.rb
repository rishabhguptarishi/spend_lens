# frozen_string_literal: true

class Budget < ApplicationRecord
  belongs_to :user
  belongs_to :category

  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :month, numericality: { in: 1..12 }, allow_nil: true
  validates :year, numericality: { greater_than: 2000 }, allow_nil: true

  # Monthly budget (month + year set) or general budget (both nil)
  scope :for_period, ->(month, year) { where(month: month, year: year) }
  scope :general, -> { where(month: nil, year: nil) }

  def spent_in_period(month:, year:)
    Transaction
      .joins(statement: :bank_account)
      .where(bank_accounts: { user_id: user_id })
      .where(transaction_type: 'debit')
      .where(category_id: category_id)
      .where("EXTRACT(MONTH FROM transactions.date) = ?", month)
      .where("EXTRACT(YEAR FROM transactions.date) = ?", year)
      .sum(:amount)
      .to_f
  end

  def remaining(month:, year:)
    amount.to_f - spent_in_period(month: month, year: year)
  end
end
