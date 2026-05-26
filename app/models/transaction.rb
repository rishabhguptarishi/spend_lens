class Transaction < ApplicationRecord
  include BankTransactionScopes

  belongs_to :statement
  # Phase 6 §G14: user_id is denormalized onto the row so user-scoped
  # queries don't need a 3-table join (transactions → statements →
  # bank_accounts). Currently nullable for legacy rows pre-Phase-6;
  # after every writer is updated and any holdouts are backfilled a
  # follow-up migration will flip this to NOT NULL.
  belongs_to :user, optional: true
  belongs_to :category, optional: true

  has_one :investment_suggestion, foreign_key: :transaction_id, dependent: :destroy, inverse_of: :source_transaction
  has_one :investment_transaction, foreign_key: :transaction_id, dependent: :nullify, inverse_of: :source_transaction

  before_validation :assign_user_from_statement, on: :create

  private

  # Belt-and-suspenders: every caller is updated to set user_id
  # explicitly, but this callback ensures rows that go through the older
  # `@statement.transactions.create!` path still get user_id without
  # touching every writer. Cheap (one already-loaded association
  # traversal) and safe.
  def assign_user_from_statement
    return if user_id.present?
    return unless statement

    self.user_id = statement.bank_account&.user_id
  end
end
