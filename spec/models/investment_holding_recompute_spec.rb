# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentHolding, "#recompute_totals!", type: :model do
  let(:user) { make_user }
  let(:account) { user.investment_accounts.create!(name: "Broker", account_kind: "broker") }
  let(:holding) do
    user.investment_holdings.create!(
      investment_account: account,
      asset_class: "stock",
      name: "INFY",
      invested_amount: 0,
      units: 0,
    )
  end

  def add_tx(kind:, amount:, units: 0)
    user.investment_transactions.create!(
      investment_account: account,
      investment_holding: holding,
      date: Date.new(2026, 4, 1),
      kind: kind,
      amount: amount,
      units: units,
      source: "manual",
    )
  end

  it "sums inflow kinds into invested_amount" do
    add_tx(kind: "buy", amount: 5_000, units: 10)
    add_tx(kind: "sip", amount: 2_000, units: 4)
    holding.recompute_totals!
    expect(holding.invested_amount.to_f).to eq(7_000.0)
    expect(holding.units.to_f).to eq(14.0)
  end

  it "subtracts outflow kinds from invested_amount" do
    add_tx(kind: "buy",  amount: 10_000, units: 20)
    add_tx(kind: "sell", amount: 3_000,  units: 6)
    holding.recompute_totals!
    expect(holding.invested_amount.to_f).to eq(7_000.0)
    expect(holding.units.to_f).to eq(14.0)
  end

  it "ignores neutral kinds like 'dividend' and 'interest'" do
    add_tx(kind: "buy",      amount: 5_000)
    add_tx(kind: "dividend", amount: 200)
    add_tx(kind: "interest", amount: 50)
    holding.recompute_totals!
    expect(holding.invested_amount.to_f).to eq(5_000.0)
  end

  it "floors invested_amount and units at 0 (never goes negative)" do
    add_tx(kind: "sell", amount: 1_000, units: 2)
    holding.recompute_totals!
    expect(holding.invested_amount.to_f).to eq(0.0)
    expect(holding.units.to_f).to eq(0.0)
  end

  it "rebuilds a holding that was corrupted by the old transfer_out broker bug" do
    # Simulates a holding that the acceptor left at 0 because the kind was
    # 'transfer_out' but the user actually bought (debit to broker).
    add_tx(kind: "transfer_out", amount: 5_000)
    add_tx(kind: "transfer_out", amount: 3_000)
    holding.update!(invested_amount: 0)

    # Then we fix the kind (as the data migration does) and recompute.
    holding.investment_transactions.update_all(kind: "buy")
    holding.recompute_totals!

    expect(holding.invested_amount.to_f).to eq(8_000.0)
  end
end
