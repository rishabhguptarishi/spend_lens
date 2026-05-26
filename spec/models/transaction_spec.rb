# frozen_string_literal: true

require "rails_helper"

RSpec.describe Transaction, type: :model do
  let(:user) { make_user }
  let(:bank_account) { make_bank_account(user: user) }
  let(:statement) { make_statement(bank_account: bank_account) }

  describe "associations" do
    it "belongs to a statement" do
      expect(described_class.reflect_on_association(:statement).macro).to eq(:belongs_to)
    end

    it "belongs to a category (optional)" do
      assoc = described_class.reflect_on_association(:category)
      expect(assoc.macro).to eq(:belongs_to)
      expect(assoc.options[:optional]).to be true
    end
  end

  describe "BankTransactionScopes (concern)" do
    let(:range) { Date.new(2026, 4, 1)..Date.new(2027, 3, 31) }

    before do
      make_transaction(statement: statement, date: Date.new(2026, 5, 1), description: "SALARY APRIL", amount: 100_000, transaction_type: "credit")
      make_transaction(statement: statement, date: Date.new(2026, 5, 2), description: "SWIGGY", amount: 350, transaction_type: "debit")
      make_transaction(statement: statement, date: Date.new(2025, 12, 1), description: "OUT OF RANGE", amount: 999, transaction_type: "credit")
    end

    describe ".for_user" do
      it "scopes by user_id and date range" do
        txs = described_class.for_user(user.id, date_range: range)
        expect(txs.count).to eq(2)
      end
    end

    describe ".sum_credits_matching_description" do
      it "sums credits matching the regex pattern" do
        total = described_class.sum_credits_matching_description(
          user.id,
          date_range: range,
          pattern: "(salary|payroll)"
        )
        expect(total).to eq(100_000)
      end

      it "returns 0 when nothing matches" do
        total = described_class.sum_credits_matching_description(
          user.id,
          date_range: range,
          pattern: "(unmatched)"
        )
        expect(total.to_f).to eq(0.0)
      end
    end
  end
end
