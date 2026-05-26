# frozen_string_literal: true

require "rails_helper"

# Phase 6 §G16 + §G17: the persist + portfolio extraction layers run
# inside a row-locked transaction. Verifies:
#   - Already-parsed statements short-circuit on a second invocation.
#   - A failure in portfolio extraction rolls back the persisted transactions
#     (no half-written state).
RSpec.describe StatementParserService, "atomicity (Phase 6 §G16 + §G17)" do
  let(:user) { make_user }
  let(:bank) { make_bank_account(user: user) }
  let(:statement) do
    s = make_statement(bank_account: bank, status: "pending")
    s.file.attach(io: StringIO.new("Date,Description,Debit,Credit,Balance\n01/04/2025,COFFEE,100,,4900"), filename: "test.csv", content_type: "text/csv")
    s
  end

  before do
    # Avoid the external categorizer hitting an LLM in tests.
    allow_any_instance_of(TransactionCategorizationService).to receive(:categorize).and_return(nil)
    # AI extractor returns nothing — keeps the test deterministic; the
    # regex path is exercised end-to-end.
    allow_any_instance_of(AiStatementExtractorService).to receive(:extract_transactions).and_return([])
  end

  describe "G16 — short-circuit on already-parsed statements" do
    it "doesn't re-persist transactions when status is already 'parsed'" do
      described_class.new(statement).call
      first_count = statement.transactions.count
      expect(first_count).to be > 0

      # Second call: should see status='parsed' inside the lock and bail.
      expect_any_instance_of(StatementParsing::Persister).not_to receive(:persist)
      described_class.new(statement).call
      expect(statement.reload.transactions.count).to eq(first_count)
    end
  end

  describe "G17 — transactional rollback on portfolio extraction failure" do
    it "rolls back persisted transactions when portfolio extraction raises inside the lock" do
      svc = described_class.new(statement)
      # Stub the specific instance to avoid private-method stubbing
      # subtleties with allow_any_instance_of.
      def svc.run_portfolio_extraction(*); raise StandardError, "explosion"; end

      svc.call

      reloaded = statement.reload
      expect(reloaded.transactions.count).to eq(0)
      expect(reloaded.status).to eq("failed")
    end
  end
end
