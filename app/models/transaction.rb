class Transaction < ApplicationRecord
  include BankTransactionScopes

  belongs_to :statement
  belongs_to :category, optional: true

  has_one :investment_suggestion, foreign_key: :transaction_id, dependent: :destroy, inverse_of: :source_transaction
  has_one :investment_transaction, foreign_key: :transaction_id, dependent: :nullify, inverse_of: :source_transaction
end
