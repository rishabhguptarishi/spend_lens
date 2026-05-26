# frozen_string_literal: true

require "rails_helper"

RSpec.describe StatementParsing::PortfolioExtractor, type: :service do
  let(:user) { make_user }

  # Real text-extracted layout from an ICICI consolidated statement.
  # The summary block (PPF balance), FIXED DEPOSITS table, and
  # RECURRING DEPOSITS table all live on page 1 of the PDF.
  let(:icici_text) do
    <<~TEXT
      Statement of Account — ICICI Bank
      Visit www.icicibank.com
      Summary of Accounts held under Cust ID: 565068715 as on March 31, 2026

       ACCOUNT DETAILS - INR

      ACCOUNT TYPE                            A/c BALANCE(I)    FIXED DEPOSITS (LINKED) BAL.(II)           TOTAL BALANCE(I+II)        NOMINATION
      PPF A/c 000418336506                         3,83,025.00                                 0.00                    3,83,025.00     Registered
      Savings A/c 057001525713                     4,60,983.85                                 0.00                    4,60,983.85     Registered
      TOTAL                                        8,44,008.85                                 0.00                    8,44,008.85



       FIXED DEPOSITS - INR


      DEPOSIT NO.     OPEN DATE         DEP.AMT.# ROI%                  PERIOD       MAT.AMT.^          MAT.DATE         BALANCE *     NOMINATION
      153913018495     07-02-2026         50,000.00    6.50             60 Mths         69,021.00       07-02-2031         50,489.00     Registered
      153913018496     07-02-2026         50,000.00    6.50       36 Mths 1 Day         60,681.00       08-02-2029         50,489.00     Registered
      057013042127     10-06-2021         40,000.00    5.35             60 Mths         52,175.00       10-06-2026         51,650.00     Registered
      TOTAL                                                                                                              1,52,628.00



       RECURRING DEPOSITS - INR

      DEPOSIT NO.     OPEN DATE         DEP.AMT.# ROI%                  PERIOD       MAT.AMT.^          MAT.DATE         BALANCE *     NOMINATION

      153925003301     07-02-2026           5,000.00   6.50             39 Mths       2,17,520.00       07-05-2029         10,071.00     Registered
      TOTAL                                                                                                                10,071.00


      Statement of Transactions in Account Number: 000418336506 in INR for the period April 01, 2025 - March 31, 2026
    TEXT
  end

  describe "ICICI consolidated statement" do
    subject(:result) { described_class.new(statement: nil, content: icici_text, user: user).call }

    it "creates a PPF holding with the current balance and the account number as folio" do
      result
      ppf = user.investment_holdings.find_by(asset_class: "ppf")
      expect(ppf).to be_present
      expect(ppf.folio).to eq("000418336506")
      expect(ppf.invested_amount.to_f).to eq(3_83_025.00)
      expect(ppf.name).to match(/PPF.*000418336506/)
    end

    it "creates one FD holding per row in the FIXED DEPOSITS passbook" do
      result
      fds = user.investment_holdings.where(asset_class: "fd").order(:folio)
      expect(fds.map(&:folio)).to contain_exactly("057013042127", "153913018495", "153913018496")
      expect(fds.map { |h| h.invested_amount.to_f }).to contain_exactly(40_000.00, 50_000.00, 50_000.00)
    end

    it "creates an RD holding with the deposit amount as invested_amount" do
      result
      rd = user.investment_holdings.find_by(asset_class: "rd", folio: "153925003301")
      expect(rd).to be_present
      expect(rd.invested_amount.to_f).to eq(5_000.00)
    end

    it "creates buy investment_transactions on the FD open date" do
      result
      txs = user.investment_transactions.where(source: "bank_statement", asset_class: "fd").order(:date)
      expect(txs.size).to eq(3)
      expect(txs.last.kind).to eq("buy")
      expect(txs.last.amount.to_f).to eq(50_000.00)
      expect(txs.last.date).to eq(Date.new(2026, 2, 7))
    end

    it "stashes maturity_amount and interest_rate in holding metadata for the portfolio UI" do
      result
      fd = user.investment_holdings.find_by(folio: "153913018495")
      expect(fd.metadata.symbolize_keys).to include(
        interest_rate: 6.50,
        maturity_amount: 69_021.00,
      )
    end

    it "is idempotent: re-running the extractor doesn't create duplicate holdings" do
      result
      expect {
        described_class.new(statement: nil, content: icici_text, user: user).call
      }.not_to change { user.investment_holdings.count }
    end

    # Phase-0 G5: re-uploading the same statement (or a later one with an
    # updated PPF balance) must NOT overwrite invested_amount on an existing
    # PPF holding. If we did overwrite, any contributions already accrued
    # via accepted "Trf to PPF" suggestions would be silently erased, and
    # we'd also keep counting the passbook balance + future contributions
    # against each other. Contract: invested_amount is set at creation
    # time only; subsequent uploads refresh metadata.last_seen_balance.
    it "does not overwrite invested_amount on a PPF re-upload (G5)" do
      described_class.new(statement: nil, content: icici_text, user: user).call

      ppf = user.investment_holdings.find_by(asset_class: 'ppf')
      ppf.update!(invested_amount: 4_00_000.00)  # simulate accrued contributions

      described_class.new(
        statement: nil,
        content: icici_text.sub('3,83,025.00', '3,99,000.00').sub('3,83,025.00', '3,99,000.00'),
        user: user
      ).call

      ppf.reload
      expect(ppf.invested_amount.to_f).to eq(4_00_000.00)
      expect(ppf.metadata['last_seen_balance']).to eq(3_99_000.00)
    end

    it "returns a Result struct describing what changed" do
      expect(result).to have_attributes(
        holdings_created: 5,            # 1 PPF + 3 FDs + 1 RD
        transactions_created: 4,        # 3 FD buys + 1 RD buy
      )
    end
  end

  describe "non-ICICI statements" do
    it "is a no-op for HDFC statements (no portfolio tables to extract)" do
      text = <<~TXT
        Statement for HDFC Bank
        10/04/2026  SWIGGY BANGALORE         350.00      99,650.00
      TXT
      result = described_class.new(statement: nil, content: text, user: user).call
      expect(result).to be_empty
      expect(user.investment_holdings).to be_empty
    end

    it "is a no-op when content is empty" do
      result = described_class.new(statement: nil, content: "", user: user).call
      expect(result).to be_empty
    end
  end
end
