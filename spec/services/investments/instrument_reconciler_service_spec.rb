# frozen_string_literal: true

require 'rails_helper'

# The realistic state the reconciler runs against:
#   - Legacy holdings created BEFORE Phase 1 don't have identity_key set
#   - Multiple writers forked parallel rows for the same instrument
#   - Backfill runs the reconciler to collapse those rows by computed key
#
# In these specs we simulate that state by creating holdings without
# setting identity_key (allowed by the partial unique index) and
# letting the reconciler compute the canonical key. We bypass the
# before_validation callback by toggling identity_key back to nil
# right after create — this is closer to legacy data than override.
RSpec.describe Investments::InstrumentReconcilerService do
  let(:user) { make_user }
  let(:broker_account) { make_investment_account(user: user, name: 'Zerodha', provider: 'Zerodha') }
  let(:cdsl_account)   { make_investment_account(user: user, name: 'CDSL CAS', provider: 'CDSL') }

  # Build a legacy-state holding: identity_key=nil at creation (mimics
  # a row created before the Phase-1 migration). The auto-assign
  # before_validation callback is bypassed by stubbing it on the
  # singleton class for just this object.
  def legacy_stock_holding(account:, name:, symbol: 'INE002A01018', created_at: nil)
    h = user.investment_holdings.new(
      investment_account: account,
      asset_class: 'stock',
      name: name,
      symbol: symbol,
      metadata: { isin: symbol },
    )
    h.define_singleton_method(:assign_identity_key) { }
    h.save!
    h.update_columns(created_at: created_at) if created_at
    h
  end

  it 'is a no-op when no duplicates exist' do
    legacy_stock_holding(account: broker_account, name: 'Reliance')

    result = described_class.merge_duplicates_for(user)
    expect(result.merges).to eq(0)
    expect(result).to be_empty
  end

  it 'merges two stock holdings with the same computed ISIN into the oldest one' do
    winner = legacy_stock_holding(account: broker_account, name: 'Reliance (broker)', created_at: 2.months.ago)
    later  = legacy_stock_holding(account: cdsl_account, name: 'Reliance Industries Ltd [CDSL]', created_at: 1.week.ago)

    user.investment_transactions.create!(
      investment_account: cdsl_account,
      investment_holding: later,
      date: 2.weeks.ago.to_date,
      kind: 'buy',
      amount: 12_000.0,
      asset_class: 'stock',
      source: 'cdsl_cas',
      financial_year_start: FinancialYear.start_year_for(2.weeks.ago.to_date),
    )

    result = described_class.merge_duplicates_for(user)

    expect(result.merges).to eq(1)
    expect(result.transactions_moved).to eq(1)
    expect(user.investment_holdings.count).to eq(1)
    expect(user.investment_holdings.first).to eq(winner)
    expect(winner.reload.investment_transactions.count).to eq(1)
    expect(winner.identity_key).to eq('INE002A01018')
  end

  it 'merges metadata from the loser into the winner (winner wins conflicts)' do
    winner = legacy_stock_holding(account: broker_account, name: 'Reliance', created_at: 2.months.ago)
    winner.update!(metadata: { isin: 'INE002A01018', source: 'broker_csv', exchange: 'NSE' })

    loser = legacy_stock_holding(account: cdsl_account, name: 'Reliance Industries Ltd', created_at: 1.week.ago)
    loser.update!(metadata: { isin: 'INE002A01018', source: 'cdsl_cas', dp_code: 'IN300095' })

    described_class.merge_duplicates_for(user)
    winner.reload
    expect(winner.metadata['exchange']).to eq('NSE')
    expect(winner.metadata['dp_code']).to eq('IN300095')
    expect(winner.metadata['source']).to eq('broker_csv') # winner wins
  end

  it 'recomputes totals on the winner so they reflect all merged transactions' do
    winner = legacy_stock_holding(account: broker_account, name: 'Reliance (broker)', created_at: 2.months.ago)
    loser  = legacy_stock_holding(account: cdsl_account, name: 'Reliance Ltd', created_at: 1.week.ago)

    user.investment_transactions.create!(
      investment_holding: winner, investment_account: broker_account,
      date: Date.new(2026, 4, 5), kind: 'buy', amount: 5_000.0,
      asset_class: 'stock', source: 'broker_import', financial_year_start: 2026,
    )
    user.investment_transactions.create!(
      investment_holding: loser, investment_account: cdsl_account,
      date: Date.new(2026, 4, 6), kind: 'buy', amount: 3_000.0,
      asset_class: 'stock', source: 'cdsl_cas', financial_year_start: 2026,
    )

    described_class.merge_duplicates_for(user)
    winner.reload
    expect(winner.invested_amount.to_f).to eq(8_000.00)
  end

  it 'ignores holdings without an identity_key (manual entries, real_estate, etc.)' do
    user.investment_holdings.create!(
      investment_account: broker_account, asset_class: 'real_estate', name: 'Bangalore Flat',
    )
    user.investment_holdings.create!(
      investment_account: broker_account, asset_class: 'real_estate', name: 'Bangalore Flat 2',
    )

    result = described_class.merge_duplicates_for(user)
    expect(result.merges).to eq(0)
    expect(user.investment_holdings.count).to eq(2)
  end

  it 'is idempotent: a second run with no new duplicates is a no-op' do
    legacy_stock_holding(account: broker_account, name: 'A', created_at: 2.months.ago)
    legacy_stock_holding(account: cdsl_account, name: 'B', created_at: 1.week.ago)

    described_class.merge_duplicates_for(user)
    expect(described_class.merge_duplicates_for(user).merges).to eq(0)
  end
end
