# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentTransaction, type: :model do
  let(:user) { make_user }

  describe "validations" do
    it "requires date, kind, amount, financial_year_start" do
      tx = user.investment_transactions.new
      expect(tx).not_to be_valid
      expect(tx.errors.attribute_names).to include(:date, :kind, :amount)
    end

    it "rejects unknown kinds" do
      expect(user.investment_transactions.new(date: Date.today, kind: "bogus", amount: 1, source: "manual")).not_to be_valid
    end

    it "rejects unknown sources" do
      expect(user.investment_transactions.new(date: Date.today, kind: "buy", amount: 1, source: "bogus")).not_to be_valid
    end
  end

  describe "before_validation :set_financial_year" do
    it "derives financial_year_start from date" do
      tx = user.investment_transactions.new(date: Date.new(2026, 5, 10), kind: "buy", amount: 1000, source: "manual")
      tx.valid?
      expect(tx.financial_year_start).to eq(2026)
    end

    it "uses previous calendar year for Jan-Mar dates" do
      tx = user.investment_transactions.new(date: Date.new(2026, 2, 10), kind: "buy", amount: 1000, source: "manual")
      tx.valid?
      expect(tx.financial_year_start).to eq(2025)
    end
  end

  describe ".for_fy scope" do
    before do
      user.investment_transactions.create!(date: Date.new(2026, 5, 1), kind: "buy", amount: 1000, source: "manual")
      user.investment_transactions.create!(date: Date.new(2025, 5, 1), kind: "buy", amount: 1000, source: "manual")
    end

    it "filters by financial_year_start" do
      expect(user.investment_transactions.for_fy(2026).count).to eq(1)
      expect(user.investment_transactions.for_fy(2025).count).to eq(1)
    end
  end
end
