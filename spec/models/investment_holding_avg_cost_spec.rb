# frozen_string_literal: true

require "rails_helper"

# Phase 6 §G4: avg_cost is now wired via before_save.
RSpec.describe InvestmentHolding, "avg_cost (Phase 6 §G4)" do
  let(:user) { make_user }
  let(:account) { make_investment_account(user: user) }

  it "computes avg_cost from invested_amount / units on save" do
    h = make_investment_holding(user: user, investment_account: account, asset_class: "stock", units: 100, invested_amount: 25_000)
    expect(h.avg_cost.to_f).to eq(250.0)
  end

  it "updates avg_cost when invested_amount changes" do
    h = make_investment_holding(user: user, investment_account: account, asset_class: "stock", units: 100, invested_amount: 25_000)
    h.update!(invested_amount: 30_000)
    expect(h.avg_cost.to_f).to eq(300.0)
  end

  it "updates avg_cost when units changes" do
    h = make_investment_holding(user: user, investment_account: account, asset_class: "stock", units: 100, invested_amount: 25_000)
    h.update!(units: 200)
    expect(h.avg_cost.to_f).to eq(125.0)
  end

  it "defaults to 0 for unit-less instruments (PPF/FD)" do
    h = make_investment_holding(user: user, investment_account: account, asset_class: "ppf", units: 0, invested_amount: 150_000)
    expect(h.avg_cost.to_f).to eq(0.0)
  end

  it "rounds to 4 decimal places (preserves precision for thin units)" do
    h = make_investment_holding(user: user, investment_account: account, asset_class: "mutual_fund", units: 7.123, invested_amount: 100)
    # 100 / 7.123 = 14.0390...
    expect(h.avg_cost.to_f).to be_within(0.001).of(14.039)
  end
end
