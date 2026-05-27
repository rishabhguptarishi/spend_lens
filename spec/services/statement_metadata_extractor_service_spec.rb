# frozen_string_literal: true

require "rails_helper"

RSpec.describe StatementMetadataExtractorService, type: :service do
  describe "AI path" do
    before do
      allow(AiClient).to receive(:chat).and_return(ai_response)
    end

    context "with a complete period range from AI" do
      let(:ai_response) do
        {
          bank_name: "HDFC Bank",
          account_last_four: "1234",
          account_type: "credit_card",
          statement_month: 4,
          statement_year: 2026,
          period_start: "2026-04-01",
          period_end: "2026-04-30",
        }.to_json
      end

      it "uses the AI-provided period" do
        result = described_class.new("HDFC Bank statement…").call
        expect(result).to include(
          bank_name: "HDFC Bank",
          last_four: "1234",
          month: 4,
          year: 2026,
          period_start: Date.new(2026, 4, 1),
          period_end: Date.new(2026, 4, 30)
        )
      end

      it "handles a full-FY statement range correctly" do
        allow(AiClient).to receive(:chat).and_return({
          bank_name: "HDFC Bank",
          account_last_four: "1234",
          statement_month: 4,
          statement_year: 2025,
          period_start: "2025-04-01",
          period_end: "2026-03-31",
        }.to_json)

        result = described_class.new("…").call
        expect(result[:period_start]).to eq(Date.new(2025, 4, 1))
        expect(result[:period_end]).to eq(Date.new(2026, 3, 31))
      end
    end

    context "with missing period range" do
      let(:ai_response) do
        {
          bank_name: "HDFC Bank",
          account_last_four: "1234",
          statement_month: 4,
          statement_year: 2026,
        }.to_json
      end

      it "falls back to the full month derived from month/year" do
        result = described_class.new("…").call
        expect(result[:period_start]).to eq(Date.new(2026, 4, 1))
        expect(result[:period_end]).to eq(Date.new(2026, 4, 30))
      end
    end

    context "with malformed period dates" do
      let(:ai_response) do
        {
          bank_name: "HDFC",
          account_last_four: "1234",
          statement_month: 4,
          statement_year: 2026,
          period_start: "not-a-date",
          period_end: "also-not-a-date",
        }.to_json
      end

      it "ignores the bad dates and falls back to the full month" do
        result = described_class.new("…").call
        expect(result[:period_start]).to eq(Date.new(2026, 4, 1))
        expect(result[:period_end]).to eq(Date.new(2026, 4, 30))
      end
    end
  end

  describe "regex fallback" do
    before { allow(AiClient).to receive(:chat).and_raise(RuntimeError, "AI down") }

    it "extracts an explicit DD/MM/YYYY period range" do
      content = <<~TXT
        HDFC Bank
        Account: ••••1234
        Statement Period: 01/04/2024 to 31/03/2025
      TXT
      result = described_class.new(content).call
      expect(result[:period_start]).to eq(Date.new(2024, 4, 1))
      expect(result[:period_end]).to eq(Date.new(2025, 3, 31))
    end

    it "extracts an ISO period range" do
      content = <<~TXT
        HDFC Bank
        Account: ••••1234
        Period: 2024-04-01 - 2025-03-31
      TXT
      result = described_class.new(content).call
      expect(result[:period_start]).to eq(Date.new(2024, 4, 1))
      expect(result[:period_end]).to eq(Date.new(2025, 3, 31))
    end

    it "falls back to the full month when no explicit range is present" do
      content = <<~TXT
        HDFC Bank
        Account: ••••1234
        April 2024
      TXT
      result = described_class.new(content).call
      expect(result[:period_start]).to eq(Date.new(2024, 4, 1))
      expect(result[:period_end]).to eq(Date.new(2024, 4, 30))
    end
  end

  describe "AI + regex merging (SBI-style multi-page layouts)" do
    # SBI prints "Welcome:" on page 1 and the actual Account Number on
    # page 2. Before the merge fix, AI saw only page 1, returned
    # "account_last_four": "0000" (the prompt placeholder), and the regex
    # extractor matched "2026" out of the date "25-05-2026". The bank
    # card ended up showing "State Bank of India •••• 0000".
    let(:sbi_content) do
      <<~TXT
                                                Welcome:
                                                As on 25-05-2026
                                                Mr. RISHABH GUPTA
        Relationship Summary
        Balance(Rs.) 481,471.02

        STATEMENT OF ACCOUNT
        Mr. RISHABH GUPTA                              State Bank of India

        Branch Code   : 11311
        Branch Name   : MAHAVEER NAGAR
        CIF Number    : 88537697405
        Account Number : 35035715556
        Product        : Savings Account
        IFSC Code      : SBIN0011311

        Statement From : 01-04-2025 to 31-03-2026
      TXT
    end

    context "when AI hallucinates '0000' for the account number" do
      before do
        allow(AiClient).to receive(:chat).and_return({
          bank_name: "SBI",
          account_last_four: "0000",
          account_type: "savings",
          statement_month: 4,
          statement_year: 2025,
        }.to_json)
      end

      it "prefers the regex-found account_last_four (5556) over the AI placeholder" do
        result = described_class.new(sbi_content).call
        expect(result[:last_four]).to eq("5556")
      end

      it "prefers the canonical bank name from BANK_FINGERPRINTS over the AI abbreviation" do
        result = described_class.new(sbi_content).call
        expect(result[:bank_name]).to eq("State Bank of India")
      end
    end

    context "when AI is unavailable" do
      before { allow(AiClient).to receive(:chat).and_raise(RuntimeError, "AI down") }

      it "still recovers the full account number from the labeled line" do
        result = described_class.new(sbi_content).call
        expect(result[:last_four]).to eq("5556")
      end

      it "detects 'State Bank of India' from the full document, not just first 10 lines" do
        result = described_class.new(sbi_content).call
        expect(result[:bank_name]).to eq("State Bank of India")
      end

      it "detects 'savings' account type from the Product label" do
        result = described_class.new(sbi_content).call
        expect(result[:account_type]).to eq("savings")
      end

      it "never returns '2026' (the calendar year) as the account_last_four" do
        result = described_class.new(sbi_content).call
        expect(result[:last_four]).not_to eq("2026")
      end

      it "detects bank from IFSC code alone (SBIN/UTIB/HDFC prefix)" do
        ifsc_only = "Some statement\nIFSC: UTIB0001955\nAccount Number: 12345678901"
        result = described_class.new(ifsc_only).call
        expect(result[:bank_name]).to eq("Axis Bank")
        expect(result[:last_four]).to eq("8901")
      end

      it "keeps HDFC as the statement bank when SBI appears later as a payee bank" do
        content = <<~TXT
          HDFC Bank
          Account Statement
          A/c No : 50100123456789
          IFSC Code : HDFC0001234

          Date Narration Withdrawal Deposit Balance
          12/04/2026 IMPS TO State Bank of India SBIN0011311 500.00 4,500.00
        TXT

        result = described_class.new(content).call
        expect(result[:bank_name]).to eq("HDFC Bank")
        expect(result[:last_four]).to eq("6789")
      end

      it "keeps ICICI as the statement bank when HDFC appears in a transaction narration" do
        content = <<~TXT
          ICICI Bank
          Statement of Account
          Account Number: 123456789012
          IFSC: ICIC0006065

          Date Narration Withdrawal Deposit Balance
          10/04/2026 NEFT TO HDFC Bank HDFC0001234 100.00 900.00
        TXT

        result = described_class.new(content).call
        expect(result[:bank_name]).to eq("ICICI Bank")
        expect(result[:last_four]).to eq("9012")
      end
    end

    context "when AI returns a different but valid last_four" do
      before do
        allow(AiClient).to receive(:chat).and_return({
          bank_name: "HDFC Bank",
          account_last_four: "1234",
          account_type: "savings",
        }.to_json)
      end

      it "keeps AI's value when it's a real number (not the '0000' placeholder)" do
        content = "HDFC Bank statement\nAccount: ••••1234\n"
        result = described_class.new(content).call
        expect(result[:last_four]).to eq("1234")
      end
    end
  end
end
