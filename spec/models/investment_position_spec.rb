# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentPosition, type: :model do
  let(:user) { make_user }
  let(:account) { make_investment_account(user: user) }
  let(:holding) { make_investment_holding(user: user, investment_account: account, name: "INFY", asset_class: "stock") }

  describe "#best_known_value" do
    it "returns current_value when live NAV is set" do
      pos = InvestmentPosition.create!(
        user: user, investment_holding: holding, asset_class: "stock", custodian: "zerodha",
        cost_basis: 1_000, current_value: 1_500, current_nav: 150.0, units: 10,
      )
      expect(pos.best_known_value).to eq(1_500.0)
    end

    it "falls back to cost_basis when current_value is missing" do
      pos = InvestmentPosition.create!(
        user: user, investment_holding: holding, asset_class: "stock", custodian: "zerodha",
        cost_basis: 1_000, units: 10,
      )
      expect(pos.best_known_value).to eq(1_000.0)
    end

    it "falls back to cost_basis when current_value is zero (NAV API returned 0)" do
      pos = InvestmentPosition.create!(
        user: user, investment_holding: holding, asset_class: "stock", custodian: "zerodha",
        cost_basis: 1_000, current_value: 0, units: 10,
      )
      expect(pos.best_known_value).to eq(1_000.0)
    end
  end

  describe "#priced_with_nav?" do
    it "is true only when current_value AND current_nav are present and positive" do
      pos = InvestmentPosition.new(current_value: 1_500, current_nav: 150.0)
      expect(pos.priced_with_nav?).to be(true)
    end

    it "is false when current_nav is nil" do
      pos = InvestmentPosition.new(current_value: 1_500, current_nav: nil)
      expect(pos.priced_with_nav?).to be(false)
    end
  end

  describe "#unrealized_gain / #unrealized_return_pct" do
    it "computes positive and negative gains correctly" do
      pos = InvestmentPosition.new(cost_basis: 1_000, current_value: 1_500)
      expect(pos.unrealized_gain).to eq(500.0)
      expect(pos.unrealized_return_pct).to eq(50.0)
    end

    it "returns nil when cost_basis is missing/zero (avoid divide-by-zero)" do
      pos = InvestmentPosition.new(cost_basis: 0, current_value: 1_500)
      expect(pos.unrealized_return_pct).to be_nil
    end

    it "returns nil when current_value is missing" do
      pos = InvestmentPosition.new(cost_basis: 1_000)
      expect(pos.unrealized_gain).to be_nil
    end
  end
end
