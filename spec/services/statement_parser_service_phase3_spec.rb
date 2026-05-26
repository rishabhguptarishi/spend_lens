# frozen_string_literal: true

require 'rails_helper'

# Phase 3 integration: verifies that StatementParserService now routes
# uploads through BankFingerprintRegistry, runs the per-bank parser, and
# stamps parser_name / parser_version / parse_quality on the Statement.
#
# We don't construct real PDFs in this suite; instead we stub
# TextExtractor to return our sanitised fixture text. That keeps the
# integration tight without dragging in pdf-reader fixtures.
RSpec.describe StatementParserService, 'Phase 3 parser wiring' do
  fixture_dir = Rails.root.join('spec/fixtures/statements')
  let(:user) { make_user }
  let(:bank_account) { make_bank_account(user: user) }

  def setup_statement_with_text(text, filename: 'sample.pdf')
    statement = bank_account.statements.create!(month: 4, year: 2026, status: 'pending')
    statement.file.attach(
      io: StringIO.new('PDF binary placeholder'),
      filename: filename,
      content_type: 'application/pdf',
    )
    allow(StatementParsing::TextExtractor).to receive(:extract).and_return(text)
    # AI services are stubbed — Ollama / Gemini aren't reachable from
    # CI and we want a deterministic flow.
    allow_any_instance_of(AiStatementExtractorService)
      .to receive(:extract_transactions).and_return([])
    allow_any_instance_of(TransactionCategorizationService)
      .to receive(:categorize).and_return(nil)
    statement
  end

  describe 'HDFC fingerprint' do
    let(:text) { File.read(fixture_dir.join('hdfc_savings_sample.txt')) }

    it 'stamps parser_name="HDFC Bank" and parser_version on the statement' do
      statement = setup_statement_with_text(text)
      described_class.new(statement).call

      statement.reload
      expect(statement.parser_name).to eq('HDFC Bank')
      expect(statement.parser_version).to eq(StatementParsing::Banks::HdfcParser::VERSION)
    end

    it 'records balance_verified=true in parse_quality' do
      statement = setup_statement_with_text(text)
      described_class.new(statement).call

      pq = statement.reload.parse_quality
      expect(pq['balance_verified']).to be true
      expect(pq['opening_balance'].to_f).to eq(25_000.0)
      expect(pq['closing_balance'].to_f).to eq(72_250.0)
      expect(pq['extraction_method']).to eq('deterministic')
    end

    it 'persists the 4 spendable transactions' do
      statement = setup_statement_with_text(text)
      described_class.new(statement).call
      expect(statement.transactions.count).to eq(4)
    end
  end

  describe 'ICICI fingerprint' do
    let(:text) { File.read(fixture_dir.join('icici_consolidated_sample.txt')) }

    it 'stamps parser_name="ICICI Bank"' do
      statement = setup_statement_with_text(text)
      described_class.new(statement).call
      expect(statement.reload.parser_name).to eq('ICICI Bank')
    end

    it 'persists ONLY spendable-section transactions (excludes PPF block)' do
      statement = setup_statement_with_text(text)
      described_class.new(statement).call
      expect(statement.transactions.count).to eq(4) # PPF section's "Contribution" is excluded
    end

    it 'runs PortfolioExtractor because the fingerprint opts into :portfolio_extraction' do
      statement = setup_statement_with_text(text)
      expect(StatementParsing::PortfolioExtractor).to receive(:new).and_call_original
      described_class.new(statement).call
    end
  end

  describe 'Axis fingerprint' do
    let(:text) { File.read(fixture_dir.join('axis_savings_sample.txt')) }

    it 'stamps parser_name="Axis Bank"' do
      statement = setup_statement_with_text(text)
      described_class.new(statement).call
      expect(statement.reload.parser_name).to eq('Axis Bank')
    end

    it 'does NOT run PortfolioExtractor (no :portfolio_extraction feature)' do
      statement = setup_statement_with_text(text)
      expect(StatementParsing::PortfolioExtractor).not_to receive(:new)
      described_class.new(statement).call
    end
  end

  describe 'SBI fingerprint' do
    let(:text) { File.read(fixture_dir.join('sbi_savings_sample.txt')) }

    it 'stamps parser_name="State Bank of India"' do
      statement = setup_statement_with_text(text)
      described_class.new(statement).call
      expect(statement.reload.parser_name).to eq('State Bank of India')
    end
  end

  describe 'Tier-2 bank (no fingerprint match)' do
    let(:text) do
      <<~TEXT
        Kotak Mahindra Bank Limited
        Account Statement
        A/C No: 1234567890 IFSC: KKBK0001234
        Period: 01/04/2026 to 30/04/2026

        Opening Balance        5,000.00

        Date         Narration                  Withdrawal      Deposit       Balance
        01/04/2026   B/F                                                       5,000.00
        05/04/2026   UPI/SOMETHING              100.00                         4,900.00
        10/04/2026   NEFT/CR                                    500.00         5,400.00

        Closing Balance        5,400.00
      TEXT
    end

    it 'falls through to the GenericParser when no fingerprint matches' do
      statement = setup_statement_with_text(text)
      described_class.new(statement).call
      statement.reload
      expect(statement.parser_name).to eq('generic')
      expect(statement.parser_version).to eq(StatementParsing::Banks::GenericParser::VERSION)
    end

    it 'still parses transactions via the generic path (no regression for Tier-2 uploads)' do
      statement = setup_statement_with_text(text)
      described_class.new(statement).call
      expect(statement.transactions.count).to be >= 1
    end
  end

  describe 'failure handling' do
    it 'marks the statement failed and does not raise when text extraction returns blank' do
      statement = bank_account.statements.create!(month: 4, year: 2026, status: 'pending')
      statement.file.attach(
        io: StringIO.new('PDF binary placeholder'),
        filename: 'sample.pdf',
        content_type: 'application/pdf',
      )
      allow(StatementParsing::TextExtractor).to receive(:extract).and_return('')
      allow_any_instance_of(AiStatementExtractorService)
        .to receive(:extract_transactions).and_return([])

      expect { described_class.new(statement).call }.not_to raise_error
      expect(statement.reload.status).to eq('failed')
    end
  end
end
