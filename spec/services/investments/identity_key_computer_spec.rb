# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Investments::IdentityKeyComputer do
  describe '.from_attrs (pure function form)' do
    it 'uses ISIN as the key for stocks when present' do
      key = described_class.from_attrs(asset_class: 'stock', isin: 'INE002A01018')
      expect(key).to eq('INE002A01018')
    end

    it 'falls back to TICKER:EXCH:SYMBOL when no ISIN' do
      key = described_class.from_attrs(asset_class: 'stock', symbol: 'INFY', exchange: 'NSE')
      expect(key).to eq('TICKER:NSE:INFY')
    end

    it 'defaults exchange to NSE when omitted' do
      key = described_class.from_attrs(asset_class: 'stock', symbol: 'TCS')
      expect(key).to eq('TICKER:NSE:TCS')
    end

    it 'uses ISIN for mutual_fund when present (CDSL-side)' do
      expect(described_class.from_attrs(asset_class: 'mutual_fund', isin: 'INF179K01BB8'))
        .to eq('INF179K01BB8')
    end

    it 'uses FOLIO:<amc>:<folio> for mutual_fund without ISIN (CAMS/KFin-side)' do
      key = described_class.from_attrs(asset_class: 'mutual_fund', folio: '11223344/HDFC', amc: 'HDFC Mutual Fund')
      expect(key).to eq('FOLIO:HDFC Mutual Fund:11223344/HDFC')
    end

    it 'returns nil for mutual_fund when neither ISIN nor folio+amc available' do
      expect(described_class.from_attrs(asset_class: 'mutual_fund')).to be_nil
    end

    it 'builds FD:<bank>:<deposit_no> for FDs' do
      key = described_class.from_attrs(asset_class: 'fd', folio: '153913018495', bank_name: 'ICICI Bank')
      expect(key).to eq('FD:ICICI Bank:153913018495')
    end

    it 'prefers IFSC over bank name when provided for FDs' do
      key = described_class.from_attrs(asset_class: 'fd', folio: '153913018495', bank_ifsc: 'ICIC0006065', bank_name: 'ICICI Bank')
      expect(key).to eq('FD:ICIC0006065:153913018495')
    end

    it 'builds RD:<bank>:<deposit_no> for RDs' do
      key = described_class.from_attrs(asset_class: 'rd', folio: '153925003301', bank_name: 'ICICI Bank')
      expect(key).to eq('RD:ICICI Bank:153925003301')
    end

    it 'builds PPF:<bank>:<account_no> for PPF' do
      key = described_class.from_attrs(asset_class: 'ppf', folio: '000418336506', bank_name: 'ICICI Bank')
      expect(key).to eq('PPF:ICICI Bank:000418336506')
    end

    it 'builds EPF:<uan> for EPF' do
      key = described_class.from_attrs(asset_class: 'epf', uan: '100123456789')
      expect(key).to eq('EPF:100123456789')
    end

    it 'builds NPS:<pran> for NPS' do
      key = described_class.from_attrs(asset_class: 'nps', pran: '123456789012')
      expect(key).to eq('NPS:123456789012')
    end

    it 'uses ISIN for REIT' do
      expect(described_class.from_attrs(asset_class: 'reit', isin: 'INE041Y01017'))
        .to eq('INE041Y01017')
    end

    it 'uses ISIN for InvIT' do
      expect(described_class.from_attrs(asset_class: 'invit', isin: 'INE219X23014'))
        .to eq('INE219X23014')
    end

    it 'builds RSU:<company>:<grant> for RSUs' do
      key = described_class.from_attrs(asset_class: 'rsu', company: 'Acme Inc', grant_id: 'GR-2026-04')
      expect(key).to eq('RSU:Acme Inc:GR-2026-04')
    end

    it 'builds ESPP:<company>:<purchase_period>' do
      key = described_class.from_attrs(asset_class: 'espp', company: 'Acme Inc', purchase_period: '2026-H1')
      expect(key).to eq('ESPP:Acme Inc:2026-H1')
    end

    it 'builds P2P:<platform>:<investor_id>' do
      key = described_class.from_attrs(asset_class: 'p2p', platform: 'LendingKart', investor_id: 'INV-99231')
      expect(key).to eq('P2P:LendingKart:INV-99231')
    end

    it 'builds FRE:<platform>:<property>:<investor> for fractional RE' do
      key = described_class.from_attrs(asset_class: 'fractional_re', platform: 'Strata', property_id: 'BLR-001', investor_id: 'U-512')
      expect(key).to eq('FRE:Strata:BLR-001:U-512')
    end

    it 'returns nil for asset classes with no canonical key (real_estate, other)' do
      expect(described_class.from_attrs(asset_class: 'real_estate')).to be_nil
      expect(described_class.from_attrs(asset_class: 'other')).to be_nil
    end

    it 'returns nil when required attrs are missing (FD without bank or deposit_no)' do
      expect(described_class.from_attrs(asset_class: 'fd', folio: '12345')).to be_nil
      expect(described_class.from_attrs(asset_class: 'fd', bank_name: 'ICICI')).to be_nil
    end

    it 'strips whitespace and collapses internal whitespace runs' do
      key = described_class.from_attrs(asset_class: 'fd', folio: '  153913018495  ', bank_name: 'ICICI  Bank ')
      expect(key).to eq('FD:ICICI Bank:153913018495')
    end
  end

  describe '.call (Active Record form)' do
    let(:user) { make_user }
    let(:account) do
      user.investment_accounts.create!(name: 'ICICI Bank — PPF', provider: 'ICICI Bank', account_kind: 'ppf')
    end

    it 'computes identity_key from a saved holding' do
      h = user.investment_holdings.build(
        investment_account: account,
        asset_class: 'ppf',
        name: 'ICICI PPF 000418336506',
        folio: '000418336506',
        metadata: { bank_name: 'ICICI Bank', account_no: '000418336506' },
      )
      expect(described_class.call(h)).to eq('PPF:ICICI Bank:000418336506')
    end

    it 'falls back to investment_account.name when provider is nil' do
      bare_account = user.investment_accounts.create!(name: 'My Bank FDs', provider: nil, account_kind: 'fd')
      h = user.investment_holdings.build(
        investment_account: bare_account,
        asset_class: 'fd',
        name: 'FD 1234',
        folio: '1234',
      )
      expect(described_class.call(h)).to eq('FD:My Bank FDs:1234')
    end
  end
end
