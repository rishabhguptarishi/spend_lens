# frozen_string_literal: true

require "rails_helper"

# Phase 6 §G14: user_id is denormalized onto transactions, with a
# before_validation callback that fills it in from
# statement.bank_account.user_id when not explicitly set.
RSpec.describe Transaction, "user_id assignment (Phase 6 §G14)" do
  let(:user) { make_user }
  let(:bank) { make_bank_account(user: user) }
  let(:statement) { make_statement(bank_account: bank, status: "parsed") }

  it "auto-fills user_id from the statement chain when not given" do
    tx = statement.transactions.create!(
      date: Date.new(2026, 6, 1), description: "TEST", amount: 100, transaction_type: "debit"
    )
    expect(tx.user_id).to eq(user.id)
  end

  it "respects an explicit user_id and doesn't overwrite it" do
    other_user = make_user(email: "other@example.com")
    tx = statement.transactions.create!(
      user: other_user, date: Date.new(2026, 6, 1), description: "TEST", amount: 100, transaction_type: "debit"
    )
    # The callback only runs when user_id is blank, so the explicit one wins.
    expect(tx.user_id).to eq(other_user.id)
  end

  it "is reachable from user.transactions association" do
    statement.transactions.create!(date: Date.new(2026, 6, 1), description: "T1", amount: 50, transaction_type: "debit")
    statement.transactions.create!(date: Date.new(2026, 6, 2), description: "T2", amount: 75, transaction_type: "credit")

    expect(user.transactions.pluck(:description)).to contain_exactly("T1", "T2")
  end
end
