# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budget, type: :model do
  let(:user) { User.create!(email: "budget@example.com", password: "password123") }
  let(:category) { user.categories.find_by(name: "Food & Dining") || user.categories.create!(name: "Food & Dining") }

  def build_budget(attrs = {})
    Budget.new({ user: user, category: category, amount: 5000 }.merge(attrs))
  end

  describe "validations" do
    it "is valid with the minimum required attributes" do
      expect(build_budget).to be_valid
    end

    it "requires amount >= 0" do
      expect(build_budget(amount: -1)).not_to be_valid
      expect(build_budget(amount: 0)).to be_valid
    end

    it "allows nil month and year (general budget)" do
      expect(build_budget(month: nil, year: nil)).to be_valid
    end

    it "rejects month outside 1..12" do
      expect(build_budget(month: 0)).not_to be_valid
      expect(build_budget(month: 13)).not_to be_valid
      expect(build_budget(month: 6)).to be_valid
    end

    it "rejects year <= 2000" do
      expect(build_budget(year: 2000)).not_to be_valid
      expect(build_budget(year: 2024)).to be_valid
    end

    it "requires user and category" do
      expect(Budget.new(amount: 1000)).not_to be_valid
    end
  end

  describe "scopes" do
    it ".for_period filters by month + year" do
      monthly = Budget.create!(user: user, category: category, amount: 1000, month: 4, year: 2026)
      general = Budget.create!(user: user, category: category, amount: 5000)

      expect(Budget.for_period(4, 2026)).to include(monthly)
      expect(Budget.for_period(4, 2026)).not_to include(general)
    end

    it ".general filters for budgets without a month/year" do
      Budget.create!(user: user, category: category, amount: 1000, month: 4, year: 2026)
      general = Budget.create!(user: user, category: category, amount: 5000)

      expect(Budget.general).to contain_exactly(general)
    end
  end

  describe "#spent_in_period and #remaining" do
    let(:budget) { Budget.create!(user: user, category: category, amount: 10_000) }

    before do
      bank = user.bank_accounts.create!(name: "HDFC", bank_name: "HDFC", account_type: "savings", last_four: "1234")
      statement = bank.statements.create!(month: 4, year: 2026, status: "processed")
      statement.transactions.create!(
        date: Date.new(2026, 4, 10),
        description: "Lunch",
        amount: 600,
        transaction_type: "debit",
        category: category
      )
      statement.transactions.create!(
        date: Date.new(2026, 4, 12),
        description: "Dinner",
        amount: 400,
        transaction_type: "debit",
        category: category
      )
      statement.transactions.create!(
        date: Date.new(2026, 5, 1),
        description: "Out of window",
        amount: 999,
        transaction_type: "debit",
        category: category
      )
    end

    it "sums only debit transactions inside the requested month/year" do
      expect(budget.spent_in_period(month: 4, year: 2026)).to eq(1000.0)
    end

    it "computes remaining as amount minus spent" do
      expect(budget.remaining(month: 4, year: 2026)).to eq(9000.0)
    end

    it "returns 0 spent for a period with no matching transactions" do
      expect(budget.spent_in_period(month: 1, year: 2026)).to eq(0.0)
    end
  end
end
