# frozen_string_literal: true

require 'rails_helper'

# Phase-0 regressions for InvestmentImports::Importer.
#
# Covers:
#   G2: MF CAS batches must stamp InvestmentTransaction#source = 'mf_cas'
#       (not the generic 'broker_import'); CDSL must stamp 'cdsl_cas'.
#   G7: All newly registered batch sources (nsdl_cas, cams_cas, kfintech_cas,
#       bank_statement) validate against InvestmentImportBatch::SOURCES.
#   G8: The canonical "Mutual Funds (CAS)" account name lives in one constant
#       so CDSL CAS rows (account_hint) and MF CAS batches (default account)
#       collapse to a single InvestmentAccount instead of forking two
#       differently-cased copies.
RSpec.describe InvestmentImports::Importer do
  let(:user) { make_user }

  describe 'source-stamping per batch type (G2)' do
    let(:rows) do
      [
        {
          date: '2026-04-05', kind: 'sip', amount: 5000.0,
          description: 'HDFC Top 100', asset_class: 'mutual_fund',
          symbol: 'INF179K01BB8', units: 12.5,
          financial_year_start: 2026,
          source: 'broker_import',  # parser still uses BaseParser default
          selected: true,
        }
      ]
    end

    it 'stamps mf_cas batches as source=mf_cas' do
      batch = user.investment_import_batches.create!(
        source: 'mf_cas', status: 'preview', financial_year_start: 2026,
        preview_rows: rows, metadata: { 'filename' => 'cas.pdf' }
      )

      described_class.new(user, batch).call
      tx = user.investment_transactions.last
      expect(tx.source).to eq('mf_cas')
    end

    it 'stamps cdsl_cas batches as source=cdsl_cas' do
      batch = user.investment_import_batches.create!(
        source: 'cdsl_cas', status: 'preview', financial_year_start: 2026,
        preview_rows: rows.map { |r| r.merge(account_hint: 'Mutual Funds (CAS)') },
        metadata: { 'filename' => 'cas.pdf' }
      )

      described_class.new(user, batch).call
      tx = user.investment_transactions.last
      expect(tx.source).to eq('cdsl_cas')
    end

    it 'stamps zerodha (and other broker CSVs) as source=broker_import' do
      batch = user.investment_import_batches.create!(
        source: 'zerodha', status: 'preview', financial_year_start: 2026,
        preview_rows: rows, metadata: { 'filename' => 'tradebook.csv' }
      )

      described_class.new(user, batch).call
      tx = user.investment_transactions.last
      expect(tx.source).to eq('broker_import')
    end
  end

  describe 'unified Mutual Funds (CAS) account (G8)' do
    let(:mf_row) do
      {
        date: '2026-04-05', kind: 'sip', amount: 1000.0,
        description: 'HDFC Top 100', asset_class: 'mutual_fund',
        symbol: 'INF179K01BB8', units: 5.0,
        financial_year_start: 2026,
        selected: true,
      }
    end

    it 'reuses the same InvestmentAccount whether the rows arrive via MF CAS or CDSL CAS' do
      mf_batch = user.investment_import_batches.create!(
        source: 'mf_cas', status: 'preview', financial_year_start: 2026,
        preview_rows: [mf_row], metadata: { 'filename' => 'mf.pdf' }
      )
      described_class.new(user, mf_batch).call

      cdsl_batch = user.investment_import_batches.create!(
        source: 'cdsl_cas', status: 'preview', financial_year_start: 2026,
        preview_rows: [mf_row.merge(account_hint: 'Mutual Funds (CAS)')],
        metadata: { 'filename' => 'cas.pdf' }
      )
      described_class.new(user, cdsl_batch).call

      mf_accounts = user.investment_accounts.where('LOWER(name) = ?', 'mutual funds (cas)')
      expect(mf_accounts.count).to eq(1)
      expect(mf_accounts.first.name).to eq(InvestmentImports::Importer::MUTUAL_FUNDS_CAS_ACCOUNT_NAME)
    end
  end

  describe 'batch source validation (G7)' do
    %w[nsdl_cas cams_cas kfintech_cas bank_statement].each do |src|
      it "accepts #{src} as a valid batch source" do
        batch = user.investment_import_batches.new(
          source: src, status: 'preview', financial_year_start: 2026,
          preview_rows: [], metadata: {}
        )
        expect(batch).to be_valid
      end
    end
  end
end
