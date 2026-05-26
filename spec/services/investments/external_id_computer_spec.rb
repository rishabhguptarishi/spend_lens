# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Investments::ExternalIdComputer do
  it 'builds bank_txn:<id> for bank_detect activities' do
    expect(described_class.call(source: 'bank_detect', transaction_id: 42))
      .to eq('bank_txn:42')
  end

  it 'returns nil for bank_detect when transaction_id missing' do
    expect(described_class.call(source: 'bank_detect')).to be_nil
  end

  it 'builds passbook:<bank>:<folio>:<date>:<kind> for bank_statement' do
    expect(described_class.call(
      source: 'bank_statement',
      provider: 'ICICI Bank',
      folio: '153913018495',
      date: Date.new(2026, 2, 7),
      kind: 'open',
    )).to eq('passbook:icici_bank:153913018495:2026-02-07:open')
  end

  it 'builds mf_cas:<folio>:<date>:<units>:<amount> with stable rounding' do
    expect(described_class.call(
      source: 'mf_cas',
      folio: '11223344/HDFC',
      date: '2026-04-05',
      units: 25.4321,
      amount: 8023.456,
    )).to eq('mf_cas:11223344/HDFC:2026-04-05:25.4321:8023.46')
  end

  it 'builds cdsl:<isin>:<date>:<units>:<kind> with default kind=snapshot' do
    expect(described_class.call(
      source: 'cdsl_cas',
      isin: 'INE002A01018',
      date: '2026-03-31',
      units: 10,
    )).to eq('cdsl:INE002A01018:2026-03-31:10.0000:snapshot')
  end

  it 'uses order_id when available for broker_import' do
    expect(described_class.call(
      source: 'broker_import',
      provider: 'Zerodha',
      order_id: 'ORD-12345',
    )).to eq('broker:Zerodha:order:ORD-12345')
  end

  it 'falls back to a tuple-based key for broker_import without order_id' do
    key = described_class.call(
      source: 'broker_import',
      provider: 'Groww',
      date: Date.new(2026, 4, 5),
      isin: 'INE002A01018',
      amount: 13_442.50,
      units: 10.0,
      kind: 'transfer_in',
    )
    expect(key).to eq('broker:Groww:2026-04-05:INE002A01018:13442.50:10.0000:transfer_in')
  end

  it 'routes tax-doc rows via document_id + row_index' do
    expect(described_class.call(
      source: 'broker_import',
      provider: 'Zerodha',
      document_id: 7,
      row_index: 3,
    )).to eq('tax_doc:7:row:3')
  end

  it 'returns nil for manual entries (no source-level dedup)' do
    expect(described_class.call(source: 'manual', date: Date.today, amount: 1000)).to be_nil
  end

  it 'returns nil for unknown sources' do
    expect(described_class.call(source: 'something_new')).to be_nil
  end

  it 'sanitises whitespace into underscores' do
    key = described_class.call(
      source: 'bank_statement',
      provider: 'ICICI Bank',
      folio: '1234 5678',
      date: '2026-02-07',
      kind: 'open',
    )
    expect(key).not_to include(' ')
  end
end
