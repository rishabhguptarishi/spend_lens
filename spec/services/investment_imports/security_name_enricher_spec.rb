# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvestmentImports::SecurityNameEnricher do
  before { Rails.cache.clear }

  # Enrichment is opt-in by default (see service docstring on why); enable it
  # for every test except the one that explicitly verifies the off-by-default
  # behavior.
  around do |example|
    if example.metadata[:skip_enable]
      example.run
    else
      original_env = ENV['CDSL_CAS_AI_ENRICH']
      ENV['CDSL_CAS_AI_ENRICH'] = 'true'
      example.run
      ENV['CDSL_CAS_AI_ENRICH'] = original_env
    end
  end

  # Rich descriptions — these pass the hallucination guard so the AI is
  # asked to polish them. The "skip when thin" case has its own describe
  # block below.
  let(:rows) do
    [
      {
        date: '2026-03-31',
        kind: 'transfer_in',
        amount: 13_442.5,
        units: 10.0,
        description: 'RELIANCEINDUSTRIESLIMITED (INE002A01018)',
        symbol: 'INE002A01018',
        asset_class: 'stock',
        account_hint: 'INDStocks',
      },
      {
        date: '2026-03-31',
        kind: 'transfer_in',
        amount: 3_706.55,
        units: 18.166,
        description: 'HDFC Mid-Cap Fund - Regular Growth (INF179K01XQ0)',
        symbol: 'INF179K01XQ0',
        asset_class: 'stock',
        account_hint: 'INDStocks',
      },
      {
        date: '2026-02-09',
        kind: 'sip',
        amount: 2999.85,
        units: 28.925,
        description: 'Axis Small Cap Fund - Regular Growth (INF846K01K01)',
        symbol: 'INF846K01K01',
        asset_class: 'mutual_fund',
        account_hint: 'Mutual Funds (CAS)',
      },
    ]
  end

  describe 'happy path' do
    let(:ai_response) do
      {
        securities: [
          { isin: 'INE002A01018', name: 'Reliance Industries Limited' },
          { isin: 'INF179K01XQ0', name: 'HDFC Mid-Cap Fund - Direct Plan - Growth' },
          { isin: 'INF846K01K01', name: 'Axis Small Cap Fund - Direct Plan - Growth' },
        ]
      }.to_json
    end

    before { allow(AiClient).to receive(:chat).and_return(ai_response) }

    it 'rewrites the description with the canonical name, keeping the ISIN suffix' do
      enriched = described_class.call(rows)
      reliance = enriched.find { |r| r[:symbol] == 'INE002A01018' }
      hdfc = enriched.find { |r| r[:symbol] == 'INF179K01XQ0' }

      expect(reliance[:description]).to eq('Reliance Industries Limited (INE002A01018)')
      expect(hdfc[:description]).to eq('HDFC Mid-Cap Fund - Direct Plan - Growth (INF179K01XQ0)')
    end

    it 'never touches numeric fields (amount/units/date/kind) even if AI returned them' do
      bad_ai = {
        securities: [
          { isin: 'INE002A01018', name: 'Reliance Industries Limited', amount: 99_999, units: 1 }
        ]
      }.to_json
      allow(AiClient).to receive(:chat).and_return(bad_ai)

      enriched = described_class.call(rows)
      reliance = enriched.find { |r| r[:symbol] == 'INE002A01018' }
      expect(reliance[:amount]).to eq(13_442.5)
      expect(reliance[:units]).to eq(10.0)
      expect(reliance[:date]).to eq('2026-03-31')
      expect(reliance[:kind]).to eq('transfer_in')
    end

    it 'sends exactly one AI request regardless of row count (one batch <= MAX_BATCH)' do
      described_class.call(rows)
      expect(AiClient).to have_received(:chat).once
    end
  end

  describe 'safety: rejects spoofed ISINs' do
    let(:malicious_ai) do
      {
        securities: [
          { isin: 'INE999X99999', name: 'Spoofed Security' },
          { isin: 'INF179K01XQ0', name: 'HDFC Mid-Cap Fund - Direct Plan - Growth' },
        ]
      }.to_json
    end

    before { allow(AiClient).to receive(:chat).and_return(malicious_ai) }

    it 'ignores ISINs not present in the input batch' do
      enriched = described_class.call(rows)
      isins = enriched.map { |r| r[:symbol] }
      expect(isins).not_to include('INE999X99999')
      # The legitimate one still got rewritten:
      expect(enriched.find { |r| r[:symbol] == 'INF179K01XQ0' }[:description])
        .to eq('HDFC Mid-Cap Fund - Direct Plan - Growth (INF179K01XQ0)')
    end
  end

  describe 'failure modes' do
    it 'returns rows unchanged when AiClient raises' do
      allow(AiClient).to receive(:chat).and_raise(StandardError, 'AI down')

      expect(described_class.call(rows)).to eq(rows)
    end

    it 'returns rows unchanged when AI returns garbage JSON' do
      allow(AiClient).to receive(:chat).and_return('this is not json at all')

      expect(described_class.call(rows)).to eq(rows)
    end

    it 'is off by default — must be opted in via CDSL_CAS_AI_ENRICH=true', :skip_enable do
      allow(AiClient).to receive(:chat)
      expect(described_class.call(rows)).to eq(rows)
      expect(AiClient).not_to have_received(:chat)
    end

    it 'tolerates rows with no ISIN by leaving them alone' do
      rows_no_isin = [{ symbol: nil, description: 'manual entry', amount: 100, date: '2026-01-01', kind: 'buy' }]
      allow(AiClient).to receive(:chat)

      expect(described_class.call(rows_no_isin)).to eq(rows_no_isin)
      expect(AiClient).not_to have_received(:chat)
    end
  end

  describe 'hallucination guard: skips rows whose raw fragment is too thin' do
    # Empirically, when the description is just an AMC initialism with no
    # scheme keyword (e.g. "HDFCAMCLTD"), Gemini/GPT confidently guess the
    # wrong fund. The enricher refuses to send these rows to the model.
    # These descriptions are AMC initialisms with NO scheme keyword (no
    # 'Fund', 'Limited', 'LTD' with a word boundary, etc.) — model has
    # nothing to verify against. Real-world examples seen in CDSL CAS PDFs.
    let(:thin_rows) do
      [
        {
          symbol: 'INF179K01XQ0',
          description: 'HDFCAMCLTD (INF179K01XQ0)',
          amount: 3706.55, units: 18.166, date: '2026-03-31', kind: 'transfer_in',
        },
        {
          symbol: 'INF194KB1AL4',
          description: 'BANDHANAMCLTD (INF194KB1AL4)',
          amount: 2683.15, units: 58.445, date: '2026-03-31', kind: 'transfer_in',
        },
      ]
    end

    let(:rich_rows) do
      [
        {
          symbol: 'INF846K01K01',
          description: 'Axis Small Cap Fund - Regular Growth (INF846K01K01)',
          amount: 2999.85, units: 28.925, date: '2026-02-09', kind: 'sip',
        },
      ]
    end

    it 'skips the AI call entirely if every row is too thin' do
      allow(AiClient).to receive(:chat)
      result = described_class.call(thin_rows)
      expect(result).to eq(thin_rows)
      expect(AiClient).not_to have_received(:chat)
    end

    it 'enriches rich rows and leaves thin rows untouched in the same batch' do
      allow(AiClient).to receive(:chat).and_return(
        { securities: [
          { isin: 'INF846K01K01', name: 'Axis Small Cap Fund - Direct Plan - Growth' }
        ] }.to_json
      )

      result = described_class.call(thin_rows + rich_rows)

      expect(result.find { |r| r[:symbol] == 'INF846K01K01' }[:description])
        .to eq('Axis Small Cap Fund - Direct Plan - Growth (INF846K01K01)')
      # Thin ones unchanged:
      thin_rows.each do |t|
        match = result.find { |r| r[:symbol] == t[:symbol] }
        expect(match[:description]).to eq(t[:description])
      end
    end

    it 'considers fragments with a word-bounded keyword like "PVT LTD" rich enough to send' do
      # "MIRAEASSETIM(I)PVT LTD" has 'LTD' with a word boundary (space-before),
      # so it passes the rich-enough gate. The model still has the keyword
      # + ISIN as cross-checks — borderline case but worth attempting.
      borderline_row = {
        symbol: 'INF769K01DM9',
        description: 'MIRAEASSETIM(I)PVT LTD (INF769K01DM9)',
        amount: 2749.14, units: 53.946, date: '2026-03-31', kind: 'transfer_in',
      }
      allow(AiClient).to receive(:chat).and_return(
        { securities: [
          { isin: 'INF769K01DM9', name: 'Mirae Asset ELSS Tax Saver Fund - Direct Plan - Growth' }
        ] }.to_json
      )
      result = described_class.call([borderline_row])
      expect(result.first[:description]).to include('Mirae Asset')
    end
  end

  describe 'caching' do
    let(:ai_response) do
      { securities: [{ isin: 'INE002A01018', name: 'Reliance Industries Limited' }] }.to_json
    end

    # Rails test env uses :null_store by default — swap in a real in-memory
    # store for these specs so we can actually exercise the cache hit path.
    around do |example|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original
    end

    before { allow(AiClient).to receive(:chat).and_return(ai_response) }

    it 'serves subsequent calls from Rails.cache without hitting AiClient again' do
      described_class.call([rows.first])
      described_class.call([rows.first])
      described_class.call([rows.first])

      expect(AiClient).to have_received(:chat).once
    end

    it 'mixes cached and uncached ISINs in a single call: only fetches the missing ones' do
      Rails.cache.write('cdsl_cas/security_name:INE002A01018', 'Reliance Industries Limited', expires_in: 90.days)
      allow(AiClient).to receive(:chat).and_return(
        { securities: [
          { isin: 'INF179K01XQ0', name: 'HDFC Mid-Cap Fund - Direct Plan - Growth' },
          { isin: 'INF846K01K01', name: 'Axis Small Cap Fund - Direct Plan - Growth' },
        ] }.to_json
      )

      enriched = described_class.call(rows)
      expect(enriched.find { |r| r[:symbol] == 'INE002A01018' }[:description])
        .to eq('Reliance Industries Limited (INE002A01018)')
      expect(enriched.find { |r| r[:symbol] == 'INF179K01XQ0' }[:description])
        .to eq('HDFC Mid-Cap Fund - Direct Plan - Growth (INF179K01XQ0)')
      expect(AiClient).to have_received(:chat).once
    end
  end
end
