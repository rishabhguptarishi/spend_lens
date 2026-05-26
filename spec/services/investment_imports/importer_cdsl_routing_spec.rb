# frozen_string_literal: true

require 'rails_helper'

# Targets the special CDSL-aware path in InvestmentImports::Importer that
# routes rows to one InvestmentAccount per broker (via :account_hint) rather
# than the single-account default used by other sources.
RSpec.describe InvestmentImports::Importer do
  let(:user) { make_user }
  let(:batch) do
    user.investment_import_batches.create!(
      source: 'cdsl_cas',
      status: 'preview',
      financial_year_start: 2025,
      preview_rows: rows,
      metadata: { 'filename' => 'cas.pdf' }
    )
  end

  let(:rows) do
    [
      {
        date: '2026-02-09',
        kind: 'sip',
        amount: 2999.85,
        description: 'Axis Small Cap Fund',
        asset_class: 'mutual_fund',
        symbol: 'INF846K01K01',
        units: 28.925,
        financial_year_start: 2025,
        source: 'broker_import',
        account_hint: 'Mutual Funds (CAS)',
        meta_kind: 'mf_txn',
        selected: true,
      },
      {
        date: '2026-03-31',
        kind: 'transfer_in',
        amount: 13_442.5,
        description: 'RELIANCEINDUSTRIESLIMITED [CDSL snapshot]',
        asset_class: 'stock',
        symbol: 'INE002A01018',
        units: 10.0,
        financial_year_start: 2025,
        source: 'broker_import',
        account_hint: 'INDStocks',
        meta_kind: 'equity_snapshot',
        selected: true,
      },
      {
        date: '2026-03-31',
        kind: 'transfer_in',
        amount: 2683.15,
        description: 'BANDHANAMCLTD [CDSL snapshot]',
        asset_class: 'stock',
        symbol: 'INF194KB1AL4',
        units: 58.445,
        financial_year_start: 2025,
        source: 'broker_import',
        account_hint: 'Groww',
        meta_kind: 'equity_snapshot',
        selected: true,
      },
    ]
  end

  it 'creates one InvestmentAccount per distinct account_hint' do
    expect { described_class.new(user, batch).call }
      .to change { user.investment_accounts.count }.by(3)

    names = user.investment_accounts.pluck(:name).sort
    expect(names).to eq(['Groww', 'INDStocks', 'Mutual Funds (CAS)'])
  end

  it 'tags the MF folio account with mf_platform and equity brokers with broker' do
    described_class.new(user, batch).call

    expect(user.investment_accounts.find_by(name: 'Mutual Funds (CAS)').account_kind).to eq('mf_platform')
    expect(user.investment_accounts.find_by(name: 'INDStocks').account_kind).to eq('broker')
    expect(user.investment_accounts.find_by(name: 'Groww').account_kind).to eq('broker')
  end

  it 'imports each row into its respective account' do
    described_class.new(user, batch).call

    mf = user.investment_accounts.find_by(name: 'Mutual Funds (CAS)')
    expect(mf.investment_transactions.pluck(:kind, :amount)).to contain_exactly(['sip', 2999.85])

    indstocks = user.investment_accounts.find_by(name: 'INDStocks')
    expect(indstocks.investment_transactions.pluck(:kind, :amount)).to contain_exactly(['transfer_in', 13_442.5])

    groww = user.investment_accounts.find_by(name: 'Groww')
    expect(groww.investment_transactions.pluck(:kind, :amount)).to contain_exactly(['transfer_in', 2683.15])
  end

  it 'marks the batch as imported with a count' do
    described_class.new(user, batch).call

    expect(batch.reload.status).to eq('imported')
    expect(batch.metadata['imported_count']).to eq(3)
  end

  it 'falls back to single-account routing when the user pre-pinned the batch to one account' do
    pinned = make_investment_account(user: user, name: 'My CDSL container')
    batch.update!(investment_account_id: pinned.id)

    expect { described_class.new(user, batch).call }
      .to change { pinned.investment_transactions.count }.by(3)
    # No per-broker accounts created since the user explicitly chose one.
    expect(user.investment_accounts.pluck(:name)).to contain_exactly('My CDSL container')
  end

  it 'is idempotent: re-running the same batch does not duplicate rows' do
    described_class.new(user, batch).call
    expect(batch.reload.status).to eq('imported')

    expect { described_class.new(user, batch).call }
      .not_to change { user.investment_transactions.count }
  end
end
