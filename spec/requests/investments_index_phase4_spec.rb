# frozen_string_literal: true

require "rails_helper"

# Phase 4 §5.7: /investments now groups holdings by identity_key (or
# id when key is nil) and surfaces confirmed_by badges per instrument.
RSpec.describe InvestmentsController, "Phase 4 instrument grouping", type: :request do
  let(:user) { make_user }
  let(:account) { make_investment_account(user: user, provider: "zerodha") }
  let(:other_account) { make_investment_account(user: user, provider: "groww") }

  before { sign_in(user) }

  it "groups two custodians of the same instrument under one row" do
    # Single canonical holding (the reconciler has already merged the
    # broker + CAS rows), with two Positions — one per custodian. The
    # controller should roll these up into one instrument row with a
    # 2-custodian breakdown.
    h = make_investment_holding(user: user, investment_account: account, name: "INFY", asset_class: "stock", symbol: "INFY")
    InvestmentPosition.create!(user: user, investment_holding: h, asset_class: "stock", custodian: "zerodha", cost_basis: 30_000, units: 100)
    InvestmentPosition.create!(user: user, investment_holding: h, asset_class: "stock", custodian: "groww",   cost_basis: 20_000, units: 100)

    get investments_path, headers: { "X-Inertia" => "true" }
    expect(response).to be_successful

    body = JSON.parse(response.body)
    instruments = body.dig("props", "instruments")
    expect(instruments).to be_an(Array)
    expect(instruments.size).to eq(1)
    expect(instruments.first["cost_basis"]).to eq(50_000.0)
    expect(instruments.first["custodians"].size).to eq(2)
    expect(instruments.first["custodians"].map { |c| c["name"] }).to match_array(%w[zerodha groww])
  end

  it "surfaces confirmed_by sources from underlying activities" do
    h = make_investment_holding(user: user, investment_account: account, name: "INFY", asset_class: "stock", symbol: "INFY")
    InvestmentPosition.create!(user: user, investment_holding: h, asset_class: "stock", custodian: "zerodha", cost_basis: 30_000, units: 100)
    user.investment_transactions.create!(
      date: Date.new(2026, 4, 1), kind: "buy", amount: 30_000, units: 100,
      investment_holding: h, investment_account: account, asset_class: "stock",
      source: "broker_import", confirmed_by: ["cdsl_cas"],
    )

    get investments_path, headers: { "X-Inertia" => "true" }
    expect(response).to be_successful
    body = JSON.parse(response.body)
    confirmed_by = body.dig("props", "instruments", 0, "confirmed_by") || []
    expect(confirmed_by).to include("broker_import").or include("cdsl_cas")
  end
end
