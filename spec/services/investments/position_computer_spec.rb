# frozen_string_literal: true

require "rails_helper"

RSpec.describe Investments::PositionComputer, type: :service do
  let(:user) { make_user }
  let(:account) { make_investment_account(user: user, provider: "zerodha", name: "Zerodha demat") }
  let(:holding) do
    make_investment_holding(user: user, investment_account: account, name: "INFY", asset_class: "stock", symbol: "INFY", units: 10, invested_amount: 1_000)
  end

  # Default fake nav_fetcher returns nil — i.e. no NAV available. Specs
  # that exercise the NAV path inject a stub that returns a cache row.
  let(:nav_fetcher) { instance_double(Investments::NavFetcher, fetch: nil) }

  subject(:computer) { described_class.new(user, nav_fetcher: nav_fetcher) }

  def make_activity(kind:, amount:, units: nil, **opts)
    user.investment_transactions.create!(
      date: opts[:date] || Date.new(2026, 4, 1),
      kind: kind,
      amount: amount,
      units: units,
      investment_holding: holding,
      investment_account: account,
      asset_class: holding.asset_class,
      source: opts[:source] || "broker_import",
      **opts.except(:date, :source),
    )
  end

  describe "#call (no NAV, cost-basis only)" do
    it "creates one position per (holding, custodian) tuple from active activities" do
      make_activity(kind: "buy", amount: 1_000, units: 10)
      make_activity(kind: "buy", amount: 500, units: 5, date: Date.new(2026, 5, 1))

      result = computer.call
      expect(result.created).to eq(1)
      expect(result.updated).to eq(0)

      pos = user.investment_positions.first
      expect(pos.investment_holding_id).to eq(holding.id)
      expect(pos.custodian).to eq("zerodha")
      expect(pos.cost_basis.to_f).to eq(1_500.0)
      expect(pos.units.to_f).to eq(15.0)
      expect(pos.current_value).to be_nil
    end

    it "subtracts outflows from cost basis and units" do
      make_activity(kind: "buy",  amount: 1_000, units: 10)
      make_activity(kind: "sell", amount: 400,   units: 4, date: Date.new(2026, 6, 1))

      computer.call
      pos = user.investment_positions.first
      expect(pos.cost_basis.to_f).to eq(600.0)
      expect(pos.units.to_f).to eq(6.0)
    end

    it "skips superseded activities so cross-source duplicates don't double-count" do
      original = make_activity(kind: "buy", amount: 1_000, units: 10, source: "broker_import")
      superseding = make_activity(kind: "buy", amount: 1_000, units: 10, source: "cdsl_cas")
      original.update_columns(superseded_by_id: superseding.id)

      computer.call
      pos = user.investment_positions.first
      expect(pos.cost_basis.to_f).to eq(1_000.0)
      expect(pos.units.to_f).to eq(10.0)
    end

    it "is idempotent — recomputing doesn't double the rollup" do
      make_activity(kind: "buy", amount: 1_000, units: 10)
      computer.call
      first_cost = user.investment_positions.first.cost_basis.to_f

      computer.call
      expect(user.investment_positions.count).to eq(1)
      expect(user.investment_positions.first.cost_basis.to_f).to eq(first_cost)
    end

    it "garbage-collects positions whose activities have been deleted" do
      make_activity(kind: "buy", amount: 1_000, units: 10)
      computer.call
      expect(user.investment_positions.count).to eq(1)

      user.investment_transactions.destroy_all
      computer.call
      expect(user.investment_positions.count).to eq(0)
    end

    it "ignores non-stock asset classes for NAV lookup (NavFetcher not called)" do
      fd_holding = make_investment_holding(user: user, investment_account: account, name: "HDFC FD 12mo", asset_class: "fd")
      user.investment_transactions.create!(
        date: Date.new(2026, 4, 1), kind: "buy", amount: 50_000,
        investment_holding: fd_holding, investment_account: account, asset_class: "fd", source: "bank_statement",
      )

      expect(nav_fetcher).not_to receive(:fetch)
      computer.call
    end
  end

  describe "#call with NAV applied" do
    let(:mf_holding) do
      make_investment_holding(
        user: user, investment_account: account, name: "Mirae Bluechip Growth",
        asset_class: "mutual_fund", units: 100, invested_amount: 50_000,
        metadata: { "scheme_code" => "120503" },
      )
    end
    let(:cache_row) do
      MfNavCache.create!(scheme_code: "120503", scheme_name: "Mirae Bluechip Growth", nav: 75.0, nav_date: Date.new(2026, 5, 25), fetched_at: 1.hour.ago)
    end

    it "computes current_value = units × NAV when NAV is returned" do
      user.investment_transactions.create!(
        date: Date.new(2026, 4, 1), kind: "buy", amount: 50_000, units: 100,
        investment_holding: mf_holding, investment_account: account, asset_class: "mutual_fund", source: "mf_cas",
      )

      allow(nav_fetcher).to receive(:fetch).with(hash_including(scheme_code: "120503")).and_return(cache_row)
      result = computer.call

      pos = user.investment_positions.find_by(investment_holding_id: mf_holding.id)
      expect(pos.current_value.to_f).to eq(7_500.0) # 100 units × ₹75
      expect(pos.current_nav.to_f).to eq(75.0)
      expect(result.nav_priced).to eq(1)
    end
  end
end
