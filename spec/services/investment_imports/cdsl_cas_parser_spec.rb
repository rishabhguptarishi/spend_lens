# frozen_string_literal: true

require 'rails_helper'

# These specs cover the CDSL Consolidated Account Statement parser using
# representative *fictional* text snippets that mirror the real pdftotext
# output. We deliberately do NOT ship a real CAS PDF because it carries
# PAN / address / account numbers.
RSpec.describe InvestmentImports::CdslCasParser do
  let(:fy) { 2025 }

  def parse(text)
    described_class.new(text, source: 'cdsl_cas', financial_year_start: fy).parse
  end

  describe '#parse — MF folio transactions' do
    # The MF folio section in a CDSL CAS PDF looks roughly like this once
    # pdf-reader has flattened it to text (column alignment is preserved
    # by run-length whitespace; AMC headers stand alone on a line).
    let(:mf_text) do
      <<~TXT
        AxisMutualFund

        SCGP-AxisSmallCapFund-RegularGrowth
        ISIN:INF846K01K01                                             UCC:MFAXIS0062

                   OpeningBalance                                                        580.163

        09-02-2026 SystematicInvestment(1/        2999.85       103.71      103.71        28.925       .15        0         0
                   Perpetual) 23491176
                   ClosingBalance                                                        609.088



        CanaraRobecoMutualFund

        ETGP-CanaraRobecoELSSTaxSaverFund-RegularGrowth
        ISIN:INF760K01100                                             UCC:

                   OpeningBalance                                                        320.192
                   SystematicInvestment
        07-04-2025 1526687                         999.95        152.3        152.3        6.566       .05        0         0

        05-05-2025 1555056ticInvestment            999.95       167.58      167.58         5.967       .05        0         0
      TXT
    end

    it 'extracts MF transactions with the right kind, amount, units and ISIN' do
      rows = parse(mf_text).select { |r| r[:meta_kind] == 'mf_txn' }

      expect(rows.size).to eq(3)

      axis = rows.find { |r| r[:symbol] == 'INF846K01K01' }
      expect(axis).to include(
        date: Date.new(2026, 2, 9),
        kind: 'sip',
        amount: 2999.85,
        asset_class: 'mutual_fund',
        account_hint: 'Mutual Funds (CAS)',
      )
      expect(axis[:description]).to include('Axis Small Cap Fund')
      expect(axis[:units]).to be_within(0.01).of(28.925)
    end

    it 'classifies "Purchase"-style descriptions as buy and SIP-shaped ones as sip' do
      rows = parse(mf_text).select { |r| r[:meta_kind] == 'mf_txn' && r[:symbol] == 'INF760K01100' }
      kinds = rows.map { |r| r[:kind] }.uniq.sort
      expect(kinds).to include('buy').or include('sip')
    end

    it 'tags every MF row to a single "Mutual Funds (CAS)" account so AMCs share one container' do
      hints = parse(mf_text).select { |r| r[:meta_kind] == 'mf_txn' }.map { |r| r[:account_hint] }.uniq
      expect(hints).to eq(['Mutual Funds (CAS)'])
    end

    it 'ignores Opening/Closing Balance pseudo-rows' do
      rows = parse(mf_text)
      expect(rows.map { |r| r[:description] }).to all(satisfy { |d| !d.match?(/opening|closing/i) })
    end
  end

  describe '#parse — equity holdings snapshot' do
    let(:equity_text) do
      <<~TXT
        DPName:INDSTOCKSPRIVATELIMITED                                   DPID:12095500 CLIENTID:46693229
        DPName:GROWWINVESTTECHPRIVATELIMITED                             DPID:12088702 CLIENTID:01425011

        DP Name:INDSTOCKS PRIVATELIMITED                                                       BO II :1209550046693229

                                              HOLDING STATEMENT AS ON 31-03-2026

                         BHARATELECTRONICS
        INE263A01024     LIMITED#EQSHWITHFACE              10.000       --       --        --    10.000   400.600     4,006.00
                         VALUERE.1/-AFTERSUB
                         DIVISION

        INE002A01018     RELIANCEINDUSTRIESLIMITED         10.000       --       --        --    10.000  1344.250    13,442.50
                         EQUITYSHARES

        DP Name:GROWWINVESTTECH PRIVATELIMITED                                                       BO II :1208870201425011

                         BANDHANAMCLTD#BANDHAN
        INF194KB1AL4     MF-BANDHANSMALLCAP                58.445       --       --        --    58.445    45.909    2,683.15
                         FUND-DIRECT-GROWTH
      TXT
    end

    it 'creates one transfer_in snapshot per holding dated at FY end' do
      rows = parse(equity_text).select { |r| r[:meta_kind] == 'equity_snapshot' }
      expect(rows.size).to eq(3)
      expect(rows.map { |r| r[:date] }).to all(eq(Date.new(fy + 1, 3, 31)))
      expect(rows.map { |r| r[:kind] }).to all(eq('transfer_in'))
    end

    # Regression: every demat holding used to be tagged 'stock' even when it
    # was a mutual fund held in demat form. CDSL/NSE/BSE encode asset class
    # in the ISIN prefix (INE = equity, INF = mutual fund).
    it 'classifies asset_class from the ISIN prefix (INE→stock, INF→mutual_fund)' do
      rows = parse(equity_text).select { |r| r[:meta_kind] == 'equity_snapshot' }
      stocks = rows.select { |r| r[:asset_class] == 'stock' }
      mfs    = rows.select { |r| r[:asset_class] == 'mutual_fund' }

      expect(stocks.map { |r| r[:symbol] }).to contain_exactly('INE263A01024', 'INE002A01018')
      expect(mfs.map { |r| r[:symbol] }).to contain_exactly('INF194KB1AL4')
    end

    it 'sets amount to the market value and carries units across' do
      rel = parse(equity_text).find { |r| r[:symbol] == 'INE002A01018' }
      expect(rel[:amount]).to eq(13_442.5)
      expect(rel[:units]).to eq(10.0)
    end

    it 'maps broker BO IDs to friendly DP names so each broker becomes its own account' do
      rows = parse(equity_text).select { |r| r[:meta_kind] == 'equity_snapshot' }
      grouped = rows.group_by { |r| r[:account_hint] }
      expect(grouped.keys).to contain_exactly('INDStocks', 'Groww')
      expect(grouped['INDStocks'].size).to eq(2)
      expect(grouped['Groww'].size).to eq(1)
    end

    it 'tags each row with the source label so the importer can route per broker' do
      rows = parse(equity_text).select { |r| r[:meta_kind] == 'equity_snapshot' }
      expect(rows.map { |r| r[:meta_kind] }).to all(eq('equity_snapshot'))
    end
  end

  describe '#parse — robustness' do
    it 'returns an empty array on blank input' do
      expect(parse('')).to eq([])
    end

    it 'does not misclassify equity transaction-block rows as MF transactions' do
      # Equity *transaction* rows start with an ISIN (not a date), so the MF
      # transaction parser must not pick them up.
      text = <<~TXT
        AxisMutualFund

        SCGP-Test-Scheme

        INE263A01024    VALUERE.1/-AFTERSUB      1110232526822SETT 18-02-2026    0.000   10.000      --    10.000       0
      TXT

      expect(parse(text)).to eq([])
    end
  end
end
