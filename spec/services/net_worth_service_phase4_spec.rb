# frozen_string_literal: true

require "rails_helper"

# Phase 4 NetWorthService rewrite — reads from positions instead of
# holdings. Specs verify the doubled-counting trap is gone.
RSpec.describe NetWorthService, "Phase 4 position-aware" do
  let(:user) { make_user }
  let(:account) { make_investment_account(user: user, provider: "zerodha") }
  let(:holding) { make_investment_holding(user: user, investment_account: account, asset_class: "mutual_fund", name: "Mirae Bluechip") }

  it "returns position-derived totals when positions exist" do
    InvestmentPosition.create!(
      user: user, investment_holding: holding, asset_class: "mutual_fund",
      custodian: "zerodha", cost_basis: 50_000, current_value: 75_000, current_nav: 75.0, units: 1_000,
    )

    result = described_class.new(user).call
    expect(result[:total_invested]).to eq(50_000.0)
    expect(result[:total_current_value]).to eq(75_000.0)
    expect(result[:unrealized_gain]).to eq(25_000.0)
    expect(result[:nav_priced_count]).to eq(1)
  end

  it "falls back to cost_basis when no NAV is set, never double-counts" do
    InvestmentPosition.create!(
      user: user, investment_holding: holding, asset_class: "mutual_fund",
      custodian: "zerodha", cost_basis: 50_000, units: 1_000,
    )

    result = described_class.new(user).call
    expect(result[:total_current_value]).to eq(50_000.0)  # falls back to cost
    expect(result[:unrealized_gain]).to eq(0.0)
    expect(result[:nav_priced_count]).to eq(0)
  end

  it "does NOT include the legacy holdings.sum(:invested_amount) path" do
    holding.update_columns(invested_amount: 999_999) # legacy stale value

    InvestmentPosition.create!(
      user: user, investment_holding: holding, asset_class: "mutual_fund",
      custodian: "zerodha", cost_basis: 50_000, units: 1_000,
    )

    result = described_class.new(user).call
    expect(result[:total_invested]).to eq(50_000.0) # from positions, not holdings
  end

  it "groups by asset class with cost and current values separately" do
    other_holding = make_investment_holding(user: user, investment_account: account, asset_class: "stock", name: "INFY")
    InvestmentPosition.create!(user: user, investment_holding: holding, asset_class: "mutual_fund",
                               custodian: "zerodha", cost_basis: 50_000, current_value: 75_000, current_nav: 75.0, units: 1_000)
    InvestmentPosition.create!(user: user, investment_holding: other_holding, asset_class: "stock",
                               custodian: "zerodha", cost_basis: 20_000, units: 100)

    result = described_class.new(user).call
    expect(result[:by_asset_class]["mutual_fund"]).to eq(50_000.0)
    expect(result[:by_asset_class]["stock"]).to eq(20_000.0)
    expect(result[:by_asset_class_current]["mutual_fund"]).to eq(75_000.0)
    expect(result[:by_asset_class_current]["stock"]).to eq(20_000.0) # falls back to cost
  end
end
