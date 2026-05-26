# frozen_string_literal: true

class InvestmentSuggestion < ApplicationRecord
  STATUSES = %w[pending accepted rejected].freeze

  belongs_to :user
  belongs_to :source_transaction, class_name: 'Transaction', foreign_key: 'transaction_id', inverse_of: :investment_suggestion

  validates :suggested_asset_class, :suggested_kind, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :transaction_id, uniqueness: true

  scope :pending, -> { where(status: 'pending') }
end
