# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BackfillInvestmentIdentityKeysJob do
  let(:user) { make_user }
  let(:account) { make_investment_account(user: user, name: 'ICICI Bank — PPF', provider: 'ICICI Bank') }

  it 'backfills identity_key on legacy holdings that have enough metadata' do
    h = user.investment_holdings.create!(
      investment_account: account,
      asset_class: 'ppf',
      name: 'ICICI PPF 000418336506',
      folio: '000418336506',
      metadata: { bank_name: 'ICICI Bank', account_no: '000418336506' },
    )
    h.update_columns(identity_key: nil) # simulate pre-migration row

    described_class.perform_now(user_id: user.id, run_reconciler: false)
    expect(h.reload.identity_key).to eq('PPF:ICICI Bank:000418336506')
  end

  it 'leaves identity_key nil when the holding has no computable key' do
    h = user.investment_holdings.create!(
      investment_account: account,
      asset_class: 'real_estate',
      name: 'Some flat',
    )
    h.update_columns(identity_key: nil)

    described_class.perform_now(user_id: user.id, run_reconciler: false)
    expect(h.reload.identity_key).to be_nil
  end

  it 'backfills external_id on activities with sufficient data' do
    statement = make_statement(bank_account: make_bank_account(user: user))
    bank_tx = make_transaction(statement: statement, description: 'Trf to PPF', amount: 2_000.0, transaction_type: 'debit')

    h = user.investment_holdings.create!(
      investment_account: account,
      asset_class: 'ppf',
      name: 'PPF',
      folio: '000418336506',
    )
    inv_tx = user.investment_transactions.create!(
      investment_account: account,
      investment_holding: h,
      source_transaction: bank_tx,
      date: Date.new(2026, 4, 5),
      kind: 'contribution',
      amount: 2_000.0,
      asset_class: 'ppf',
      source: 'bank_detect',
      financial_year_start: 2026,
    )
    inv_tx.update_columns(external_id: nil, source_priority: nil)

    described_class.perform_now(user_id: user.id, run_reconciler: false)
    expect(inv_tx.reload.external_id).to eq("bank_txn:#{bank_tx.id}")
    expect(inv_tx.source_priority).to eq(60)
  end

  it 'sets source_priority even when external_id is unset (manual entries)' do
    h = user.investment_holdings.create!(
      investment_account: account,
      asset_class: 'ppf',
      name: 'PPF',
      folio: '000418336506',
    )
    inv_tx = user.investment_transactions.create!(
      investment_account: account,
      investment_holding: h,
      date: Date.new(2026, 4, 5),
      kind: 'contribution',
      amount: 1_000.0,
      asset_class: 'ppf',
      source: 'manual',
      financial_year_start: 2026,
    )
    inv_tx.update_columns(source_priority: nil, external_id: nil)

    described_class.perform_now(user_id: user.id, run_reconciler: false)
    expect(inv_tx.reload.source_priority).to eq(40)
    expect(inv_tx.external_id).to be_nil
  end

  it 'invokes the instrument reconciler when run_reconciler is true' do
    # Legacy state: two FD rows for the same deposit number exist
    # because pre-Phase-1 writers had no identity_key. Both have
    # identity_key=nil so they don't collide on the unique index.
    h1 = user.investment_holdings.create!(
      investment_account: account, asset_class: 'fd',
      name: 'FD 1', folio: '12345678901',
      metadata: { bank_name: 'ICICI Bank' },
    )
    h1.update_columns(identity_key: nil, created_at: 2.months.ago)
    h2 = user.investment_holdings.create!(
      investment_account: account, asset_class: 'fd',
      name: 'FD 1 again', folio: '12345678901',
      metadata: { bank_name: 'ICICI Bank' },
    )
    h2.update_columns(identity_key: nil, created_at: 1.week.ago)

    result = described_class.perform_now(user_id: user.id, run_reconciler: true)
    expect(result.merges).to eq(1)
    expect(user.investment_holdings.count).to eq(1)
    expect(user.investment_holdings.first).to eq(h1)
    expect(h1.reload.identity_key).to eq('FD:ICICI Bank:12345678901')
  end

  it 'is idempotent: a second run does nothing' do
    h = user.investment_holdings.create!(
      investment_account: account,
      asset_class: 'ppf',
      name: 'PPF',
      folio: '000418336506',
      metadata: { bank_name: 'ICICI Bank', account_no: '000418336506' },
    )
    h.update_columns(identity_key: nil) # simulate legacy pre-Phase-1 row

    first  = described_class.perform_now(user_id: user.id, run_reconciler: false)
    second = described_class.perform_now(user_id: user.id, run_reconciler: false)
    expect(first.holdings_keyed).to eq(1)
    expect(second.holdings_keyed).to eq(0)
  end
end
