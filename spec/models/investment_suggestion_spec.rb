# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentSuggestion, type: :model do
  let(:user) { make_user }
  let(:bank) { make_bank_account(user: user) }
  let(:statement) { make_statement(bank_account: bank) }
  let(:txn) { make_transaction(statement: statement) }

  def build_suggestion(**overrides)
    user.investment_suggestions.new({
      source_transaction: txn,
      suggested_asset_class: "stock",
      suggested_kind: "buy",
      status: "pending",
    }.merge(overrides))
  end

  describe "validations" do
    it "is valid with minimum attributes" do
      expect(build_suggestion).to be_valid
    end

    it "enforces inclusion of status in STATUSES" do
      expect(build_suggestion(status: "bogus")).not_to be_valid
    end

    it "is unique per transaction" do
      build_suggestion.save!
      dupe = build_suggestion
      expect(dupe).not_to be_valid
      expect(dupe.errors[:transaction_id]).to be_present
    end
  end

  describe ".pending scope" do
    it "only returns pending suggestions" do
      pending = build_suggestion.tap(&:save!)
      another_txn = make_transaction(statement: statement, date: Date.new(2026, 4, 11))
      build_suggestion(source_transaction: another_txn, status: "accepted").save!

      expect(user.investment_suggestions.pending).to contain_exactly(pending)
    end
  end
end
