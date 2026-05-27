# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phase 5 retirement parsers' do
  describe InvestmentImports::EpfPassbookParser do
    it 'parses EPFO passbook contribution, interest, and withdrawal rows' do
      text = <<~TEXT
        Member Passbook
        UAN: 100200300400
        01/04/2026 Contribution March 2026 1,800.00 550.00 1,250.00
        31/03/2027 Interest for the year 4,321.50
        15/05/2027 Claim withdrawal 10,000.00
      TEXT

      rows = described_class.parse(text, source: 'epf_passbook', financial_year_start: 2026)

      expect(rows.size).to eq(5)
      expect(rows.map { |r| r[:asset_class] }.uniq).to eq(['epf'])
      expect(rows.map { |r| r[:uan] }.uniq).to eq(['100200300400'])
      expect(rows.map { |r| r[:kind] }).to include('contribution', 'interest', 'maturity')
      expect(rows.sum { |r| r[:amount] }).to eq(17_921.5)
    end
  end

  describe InvestmentImports::NpsStatementParser do
    it 'parses NPS Protean transaction statements with PRAN, tier, amount, and units' do
      csv = <<~CSV
        Date,Transaction Type,Scheme,Amount,Units
        10/04/2026,Contribution,NPS Tier I - HDFC Pension Fund,50000.00,123.456
        15/08/2026,Redemption,NPS Tier I - HDFC Pension Fund,10000.00,20.500
      CSV
      content = "PRAN: 123456789012\nTier I\n#{csv}"

      rows = described_class.parse(content, source: 'nps_statement', financial_year_start: 2026)

      expect(rows.size).to eq(2)
      expect(rows.map { |r| r[:asset_class] }.uniq).to eq(['nps'])
      expect(rows.map { |r| r[:pran] }.uniq).to eq(['123456789012'])
      expect(rows.map { |r| r[:tier] }.uniq).to eq(['Tier I'])
      expect(rows.map { |r| r[:kind] }).to eq(%w[contribution sell])
      expect(rows.first[:units]).to eq(123.456)
    end
  end

  describe InvestmentImports::AmcDirectParser do
    it 'parses AMC direct folio statements with folio, AMC, ISIN, amount, and units' do
      text = <<~TEXT
        HDFC Mutual Fund Account Statement
        Folio No: 123456/78
        HDFC Flexi Cap Fund - Direct Plan - Growth ISIN: INF179K01BB8
        05-Apr-2026 Purchase 5,000.00 100.250
        05-May-2026 Systematic Investment 5,000.00 98.750
        10-Jun-2026 Redemption 2,000.00 35.000
      TEXT

      rows = described_class.parse(text, source: 'amc_direct', financial_year_start: 2026)

      expect(rows.size).to eq(3)
      expect(rows.map { |r| r[:folio] }.uniq).to eq(['123456/78'])
      expect(rows.map { |r| r[:amc] }.uniq).to eq(['HDFC Mutual Fund'])
      expect(rows.map { |r| r[:isin] }.uniq).to eq(['INF179K01BB8'])
      expect(rows.map { |r| r[:kind] }).to eq(%w[buy sip sell])
    end
  end

  describe InvestmentImports::ParserFacade do
    it 'routes the new Phase 5 sources to their deterministic parsers' do
      epf_rows = described_class.call(
        file_content: "UAN: 100200300400\n01/04/2026 Contribution 100.00",
        filename: 'epf.txt',
        source: 'epf_passbook',
        financial_year_start: 2026
      )
      nps_rows = described_class.call(
        file_content: "PRAN: 123456789012\n10/04/2026 Contribution Tier I 50000.00 123.456",
        filename: 'nps.txt',
        source: 'nps_statement',
        financial_year_start: 2026
      )
      amc_rows = described_class.call(
        file_content: "HDFC Mutual Fund\nFolio No: 123456/78\nHDFC Fund Growth ISIN: INF179K01BB8\n05-Apr-2026 Purchase 5000.00 100.25",
        filename: 'amc.txt',
        source: 'amc_direct',
        financial_year_start: 2026
      )

      expect(epf_rows.first).to include(date: '2026-04-01', selected: true, asset_class: 'epf')
      expect(nps_rows.first).to include(date: '2026-04-10', selected: true, asset_class: 'nps')
      expect(amc_rows.first).to include(date: '2026-04-05', selected: true, asset_class: 'mutual_fund')
    end
  end
end
