# frozen_string_literal: true

require 'rails_helper'

# Realistic scenario: the instrument reconciler has already collapsed
# duplicate holdings (or new-style writers used find_by(identity_key)
# at create time), so there's ONE InvestmentHolding per real-world
# instrument with multiple activities from different sources under it.
# The activity reconciler then finds activities that describe the same
# event and links them via confirmed_by / superseded_by_id.
RSpec.describe Investments::ActivityReconcilerService do
  let(:user) { make_user }
  let(:account) { make_investment_account(user: user, name: 'Zerodha', provider: 'Zerodha') }

  let(:holding) do
    user.investment_holdings.create!(
      investment_account: account,
      asset_class: 'stock',
      name: 'Reliance Industries',
      symbol: 'INE002A01018',
      identity_key: 'INE002A01018',
    )
  end

  def make_inv_tx(source:, date: Date.new(2026, 4, 5), amount: 12_000.0, kind: 'buy', **overrides)
    user.investment_transactions.create!(
      {
        investment_account: holding.investment_account,
        investment_holding: holding,
        date: date,
        kind: kind,
        amount: amount,
        asset_class: 'stock',
        source: source,
        financial_year_start: FinancialYear.start_year_for(date),
      }.merge(overrides)
    )
  end

  it 'leaves a lone activity untouched' do
    tx = make_inv_tx(source: 'broker_import')

    result = described_class.reconcile_for(user)
    expect(result.matches).to eq(0)
    expect(tx.reload.superseded_by_id).to be_nil
    expect(tx.confirmed_by).to be_empty
  end

  it 'supersedes the lower-priority activity when a higher-priority one matches' do
    broker_tx = make_inv_tx(source: 'broker_import', date: Date.new(2026, 4, 5), amount: 12_000.0)
    cdsl_tx   = make_inv_tx(source: 'cdsl_cas',      date: Date.new(2026, 4, 5), amount: 12_000.0)

    result = described_class.reconcile_for(user)
    expect(result.matches).to eq(1)
    expect(result.supersessions).to eq(1)
    expect(broker_tx.reload.superseded_by_id).to eq(cdsl_tx.id)
    expect(cdsl_tx.reload.superseded_by_id).to be_nil
    expect(cdsl_tx.confirmed_by).to include('broker_import')
  end

  it 'tolerates ±1 day date drift' do
    broker_tx = make_inv_tx(source: 'broker_import', date: Date.new(2026, 4, 5))
    cdsl_tx   = make_inv_tx(source: 'cdsl_cas', date: Date.new(2026, 4, 6))

    described_class.reconcile_for(user)
    expect(broker_tx.reload.superseded_by_id).to eq(cdsl_tx.id)
  end

  it 'tolerates ≤2% amount drift' do
    broker_tx = make_inv_tx(source: 'broker_import', amount: 10_000.0)
    cdsl_tx   = make_inv_tx(source: 'cdsl_cas', amount: 10_150.0) # 1.5% off

    described_class.reconcile_for(user)
    expect(broker_tx.reload.superseded_by_id).to eq(cdsl_tx.id)
  end

  it 'does NOT match when amounts differ by more than 2% AND more than ₹50' do
    broker_tx = make_inv_tx(source: 'broker_import', amount: 10_000.0)
    cdsl_tx   = make_inv_tx(source: 'cdsl_cas', amount: 12_000.0) # 20% off

    described_class.reconcile_for(user)
    expect(broker_tx.reload.superseded_by_id).to be_nil
    expect(cdsl_tx.reload.superseded_by_id).to be_nil
  end

  it 'does NOT match across different instruments even with same date+amount' do
    other_holding = user.investment_holdings.create!(
      investment_account: account, asset_class: 'stock',
      name: 'Infosys', symbol: 'INE009A01021', identity_key: 'INE009A01021',
    )
    a = make_inv_tx(source: 'broker_import')
    b = user.investment_transactions.create!(
      investment_account: account, investment_holding: other_holding,
      date: Date.new(2026, 4, 5), kind: 'buy', amount: 12_000.0,
      asset_class: 'stock', source: 'cdsl_cas', financial_year_start: 2026,
    )

    described_class.reconcile_for(user)
    expect(a.reload.superseded_by_id).to be_nil
    expect(b.reload.superseded_by_id).to be_nil
  end

  it 'does NOT match different kinds (buy vs dividend) at the same date+amount' do
    buy = make_inv_tx(source: 'broker_import', kind: 'buy')
    div = make_inv_tx(source: 'cdsl_cas', kind: 'dividend')

    described_class.reconcile_for(user)
    expect(buy.reload.superseded_by_id).to be_nil
    expect(div.reload.superseded_by_id).to be_nil
  end

  it 'appends confirmed_by but does NOT supersede when matched rows share priority' do
    a = make_inv_tx(source: 'broker_import', amount: 12_000.0)
    b = make_inv_tx(source: 'broker_import', amount: 12_000.0, date: Date.new(2026, 4, 6))

    result = described_class.reconcile_for(user)
    expect(result.supersessions).to eq(0)
    expect(result.confirmations).to eq(1)
    expect(a.reload.superseded_by_id).to be_nil
    expect(b.reload.superseded_by_id).to be_nil
    # The earlier-created row is treated as canonical and gets a
    # confirmed_by entry from the matched same-priority sibling.
    expect(a.confirmed_by).to include('broker_import')
  end

  it 'is idempotent: running twice does not create extra supersessions' do
    make_inv_tx(source: 'broker_import', amount: 12_000.0)
    make_inv_tx(source: 'cdsl_cas', amount: 12_000.0)

    first  = described_class.reconcile_for(user)
    second = described_class.reconcile_for(user)
    expect(first.supersessions).to eq(1)
    expect(second.supersessions).to eq(0)
  end
end
