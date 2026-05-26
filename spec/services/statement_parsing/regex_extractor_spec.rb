# frozen_string_literal: true

require "rails_helper"

RSpec.describe StatementParsing::RegexExtractor, type: :service do
  describe "CSV extraction" do
    it "parses a standard date/description/amount/type CSV" do
      csv = <<~CSV
        date,description,amount,type
        2026-04-10,SWIGGY ORDER,350,debit
        2026-04-15,SALARY APRIL,100000,credit
      CSV
      rows = described_class.new(content: csv, format: :csv).call
      expect(rows.size).to eq(2)
      expect(rows.first).to include(date: Date.new(2026, 4, 10), amount: 350.0)
    end

    it "handles separate debit/credit columns" do
      csv = <<~CSV
        date,description,debit,credit
        2026-04-10,SWIGGY,350,
        2026-04-15,SALARY,,100000
      CSV
      rows = described_class.new(content: csv, format: :csv).call
      types = rows.map { |r| r[:transaction_type] }
      expect(types).to contain_exactly("debit", "credit")
    end

    it "uses CreditKeywords to flip credit-like descriptions when type is ambiguous" do
      csv = <<~CSV
        date,description,amount
        2026-04-10,NEFT CR FROM EMPLOYER,100000
      CSV
      rows = described_class.new(content: csv, format: :csv).call
      expect(rows.first[:transaction_type]).to eq("credit")
    end

    it "skips rows with blank dates" do
      csv = <<~CSV
        date,description,amount
        ,Missing date,100
        2026-04-10,Has date,200
      CSV
      rows = described_class.new(content: csv, format: :csv).call
      expect(rows.size).to eq(1)
    end

    it "returns [] for CSV without a date-like header" do
      csv = <<~CSV
        name,address
        John,42
      CSV
      rows = described_class.new(content: csv, format: :csv).call
      expect(rows).to eq([])
    end

    it "tags rows with source 'regex'" do
      csv = "date,description,amount\n2026-04-10,SWIGGY,350\n"
      rows = described_class.new(content: csv, format: :csv).call
      expect(rows).to all(include(source: "regex"))
    end
  end

  describe "PDF extraction (text-based heuristics)" do
    it "parses a simple PDF-style text block with dd/mm/yyyy dates" do
      pdf_like = <<~TEXT
        Statement for HDFC Bank
        10/04/2026  SWIGGY BANGALORE         350.00      99,650.00
        15/04/2026  SALARY APRIL 2026     100,000.00     199,650.00
      TEXT
      rows = described_class.new(content: pdf_like, format: :pdf).call
      expect(rows.size).to be >= 1
      expect(rows.map { |r| r[:description].downcase }.join).to include("swiggy")
    end

    it "returns [] when no date-like lines are present" do
      rows = described_class.new(content: "This is a summary page with no transactions.", format: :pdf).call
      expect(rows).to eq([])
    end
  end

  describe "PDF extraction — Axis Bank layout regression suite" do
    # All snippets below were taken verbatim from a real Axis Bank PRIME
    # SALARY statement (pdf-reader extracted text). Every transaction in
    # the live PDF used to parse as -₹195 because the regex caught the
    # trailing "Init.Br" branch code (e.g. 1955) as the amount, and the
    # wrap-above-date particulars cross-contaminated adjacent rows.
    let(:axis_header) do
      <<~HDR
        Statement of Axis Account No: 917010081786930 for the period
        IFSC Code: UTIB0001955
                               OPENING BALANCE                                                                        95761.93
      HDR
    end

    it "ignores the trailing Init.Br column and reads the real amount" do
      text = axis_header + "07-04-2025             Canara Robeco E/133826853/ETGP                      1000.00                            94761.93 1955\n"
      rows = described_class.new(content: text, format: :pdf).call

      expect(rows.size).to eq(1)
      expect(rows.first[:amount]).to eq(1000.00)
      expect(rows.first[:transaction_type]).to eq("debit")
    end

    it "preserves the AMC reference number in the description (no /  /  / collapse)" do
      text = axis_header + "07-04-2025             Canara Robeco E/133826853/ETGP                      1000.00                            94761.93 1955\n"
      rows = described_class.new(content: text, format: :pdf).call

      expect(rows.first[:description]).to include("Canara Robeco E/133826853/ETGP")
      expect(rows.first[:description]).not_to include("1955")
    end

    it "splits multi-digit balances correctly (no 275 + 676.93 fragmenting)" do
      # Note: the amount must be parsed as 200000.00 even when arithmetic
      # detection isn't available. Direction may flip to debit without prior
      # balance context — covered in the arithmetic spec below.
      text = axis_header + <<~TXT
        07-02-2026             GUPTA/HDFC BANK/0001Self axis                                      200000.00             275676.93 248
      TXT
      rows = described_class.new(content: text, format: :pdf).call

      expect(rows.first[:amount]).to eq(200000.00)
      expect(rows.first[:description]).to include("Self axis")
    end

    it "uses balance arithmetic to sign credits even without 'CR' in the line" do
      # Chain a debit row before so the running_balance is 75761.93 when we
      # hit the +200000 credit, mirroring how the real statement progresses
      # before the inbound NEFT lands.
      text = axis_header + <<~TXT
        07-04-2025             Withdrawal                                                       20000.00                            75761.93 1955
        07-02-2026             GUPTA/HDFC BANK/0001Self axis                                      200000.00             275761.93 248
      TXT
      rows = described_class.new(content: text, format: :pdf).call

      first, last = rows
      expect(first[:transaction_type]).to eq("debit")
      expect(last[:transaction_type]).to eq("credit")
    end

    it "attaches wrap-above-date particulars to the NEXT date row, not the previous one" do
      # In the live PDF this exact ordering caused MIRAE SIP rows to absorb
      # the interest credit's particulars and get mis-classified as
      # 'Interest Income' debits of ₹195.
      text = axis_header + <<~TXT
        09-06-2025             MIRAE ASSET ELS/138445931/TSRG                      1000.00                            89761.93 1955
                               SB:917010081786930:Int.Pd:01-04-2025 to 30-
        01-07-2025             06-2025                                                             640.00             90401.93 1955
      TXT
      rows = described_class.new(content: text, format: :pdf).call

      sip, interest = rows
      expect(sip[:description]).to     include("MIRAE ASSET ELS")
      expect(sip[:description]).not_to include("Int.Pd")
      expect(sip[:transaction_type]).to eq("debit")
      expect(interest[:description]).to include("Int.Pd")
      expect(interest[:amount]).to eq(640.00)
      expect(interest[:transaction_type]).to eq("credit")
    end

    it "classifies ACH-CR dividend payouts as credit using the wrap-above keyword" do
      # Include a preceding date row so current_tx exists when the wrap
      # appears, matching how Axis actually prints dividend payouts.
      text = axis_header + <<~TXT
        06-07-2025             Canara Robeco E/140146392/ETGP                      1000.00                            94761.93 1955
                               ACH-CR-VEDANTA LIMITED-NACH-
        08-07-2025             34153269-34153269                                                    21.00             89422.93 2567
      TXT
      rows = described_class.new(content: text, format: :pdf).call
      ach = rows.find { |r| r[:description].include?("ACH-CR") }

      expect(ach).not_to be_nil
      expect(ach[:amount]).to eq(21.00)
      expect(ach[:transaction_type]).to eq("credit")
    end

    it "totals match the printed 'TRANSACTION TOTAL' footer (full snippet)" do
      text = axis_header + <<~TXT
        07-04-2025             Canara Robeco E/133826853/ETGP                      1000.00                            94761.93 1955
        11-04-2025             MIRAE ASSET ELS/134500597/TSRG                      1000.00                            93761.93 1955
        09-06-2025             MIRAE ASSET ELS/138445931/TSRG                      1000.00                            89761.93 1955
                               SB:917010081786930:Int.Pd:01-04-2025 to 30-
        01-07-2025             06-2025                                                             640.00             90401.93 1955
      TXT
      rows = described_class.new(content: text, format: :pdf).call
      debit  = rows.select { |r| r[:transaction_type] == "debit"  }.sum { |r| r[:amount] }
      credit = rows.select { |r| r[:transaction_type] == "credit" }.sum { |r| r[:amount] }

      expect(debit).to  eq(3000.00)
      expect(credit).to eq(640.00)
    end
  end

  describe "PDF extraction — ICICI consolidated statement regression suite" do
    # The PDFs ICICI generates for "Statement of Account" contain THREE
    # interleaved blocks for accounts under the same customer ID:
    #   1) Account summary (PPF balance, savings balance)
    #   2) FIXED DEPOSITS + RECURRING DEPOSITS passbook tables
    #   3) "Statement of Transactions in Account Number: XXX" for PPF
    #   4) "Statement of Transactions in Savings Account Number: YYY" for SB
    # Before this regression suite the parser would emit (3) and (4) as a
    # single jumbled list with B/F balances showing up as ₹2.79L mystery
    # debits, PPF-side credits flipping into debits, and the section TOTAL
    # row gluing itself to whatever transaction came right before it.

    let(:icici_header) do
      <<~HDR
        Statement of Account — ICICI Bank
        Visit www.icicibank.com
        Summary of Accounts held under Cust ID: 565068715 as on March 31, 2026
        PPF A/c 000418336506                         3,83,025.00                                 0.00                    3,83,025.00     Registered
        Savings A/c 057001525713                     4,60,983.85                                 0.00                    4,60,983.85     Registered
      HDR
    end

    it "ignores transactions inside the PPF (non-savings) section entirely" do
      text = icici_header + <<~TXT

        Statement of Transactions in Account Number: 000418336506 in INR for the period April 01, 2025 - March 31, 2026

        DATE         MODE**                PARTICULARS                                                  DEPOSITS       WITHDRAWALS                BALANCE
        01-04-2025                         B/F                                                                                                  2,79,887.00
        05-04-2025                         Trf frm SB 057001525713                                       2,000.00                              2,81,887.00
                                           TOTAL                                                       1,03,138.00                 0.00         3,83,025.00


        Statement of Transactions in Savings Account Number: 057001525713 in INR for the period April 01, 2025 - March 31, 2026

        DATE         MODE**                PARTICULARS                                                  DEPOSITS       WITHDRAWALS                BALANCE
        01-04-2025                         B/F                                                                                                  1,37,551.85
        05-04-2025                         Trf to PPF 000418336506                                                             2,000.00         1,35,551.85
      TXT

      rows = described_class.new(content: text, format: :pdf).call

      expect(rows.size).to eq(1)
      expect(rows.first[:description]).to include("Trf to PPF")
      expect(rows.first[:amount]).to eq(2000.00)
      expect(rows.first[:transaction_type]).to eq("debit")
    end

    it "skips B/F opening balance rows even when they carry an Indian-comma amount" do
      text = icici_header + <<~TXT

        Statement of Transactions in Savings Account Number: 057001525713

        DATE         MODE**                PARTICULARS                                                  DEPOSITS       WITHDRAWALS                BALANCE
        01-04-2025                         B/F                                                                                                  1,37,551.85
        05-04-2025                         Trf to PPF 000418336506                                                             2,000.00         1,35,551.85
      TXT

      rows = described_class.new(content: text, format: :pdf).call
      expect(rows.size).to eq(1)
      expect(rows.first[:amount]).to eq(2000.00)
    end

    it "uses DEPOSITS column position to mark deposits as credit and withdrawals as debit" do
      text = icici_header + <<~TXT

        Statement of Transactions in Savings Account Number: 057001525713

        DATE         MODE**                PARTICULARS                                                  DEPOSITS       WITHDRAWALS                BALANCE
        05-04-2025                         Trf to PPF 000418336506                                                             2,000.00         1,35,551.85
        30-06-2025                         057001525713:Int.Pd:29-03-2025 to 29-06-2025                     952.00                              1,32,503.85
      TXT

      rows = described_class.new(content: text, format: :pdf).call
      types = rows.map { |r| [r[:amount], r[:transaction_type]] }
      expect(types).to contain_exactly([2000.0, "debit"], [952.0, "credit"])
    end

    it "stops parsing at TOTAL and resumes at the next section header" do
      text = icici_header + <<~TXT

        Statement of Transactions in Account Number: 000418336506

        DATE         MODE**                PARTICULARS                                                  DEPOSITS       WITHDRAWALS                BALANCE
        31-03-2026                         000418336506:Int.Pd:01-04-2025 to 31-03-2026                  21,138.00                              3,83,025.00
                                           TOTAL                                                       1,03,138.00                 0.00         3,83,025.00


        Statement of Transactions in Savings Account Number: 057001525713

        DATE         MODE**                PARTICULARS                                                  DEPOSITS       WITHDRAWALS                BALANCE
        30-03-2026                         057001525713:Int.Pd:31-12-2025 to 29-03-2026                   2,386.00                              4,60,983.85
                                           TOTAL                                                       6,05,432.00          2,82,000.00         4,60,983.85

        Summary of TDS/Interest on Fixed Deposits during the Period April 01, 2025 - March 31, 2026
      TXT

      rows = described_class.new(content: text, format: :pdf).call

      # PPF section interest dropped (non-spendable), TOTAL not parsed,
      # post-TOTAL "Summary of TDS" header doesn't bleed into the row.
      expect(rows.size).to eq(1)
      expect(rows.first[:amount]).to eq(2386.0)
      expect(rows.first[:description]).not_to include("TOTAL")
      expect(rows.first[:description]).not_to include("Summary of TDS")
    end

    it "captures TRF TO FD and To RD Ac rows as savings-side debits (for InvestmentDetectionService)" do
      text = icici_header + <<~TXT

        Statement of Transactions in Savings Account Number: 057001525713

        DATE         MODE**                PARTICULARS                                                  DEPOSITS       WITHDRAWALS                BALANCE
        07-02-2026                         TRF TO FD no. 153913018495                                                         50,000.00         2,28,597.85
        16-03-2026                         To RD Ac no 153925003301                                                            5,000.00         4,58,597.85
      TXT

      rows = described_class.new(content: text, format: :pdf).call

      expect(rows.map { |r| r[:description] }).to include(
        a_string_matching(/TRF TO FD no\.? 153913018495/),
        a_string_matching(/To RD Ac no 153925003301/),
      )
      expect(rows).to all(include(transaction_type: "debit"))
    end
  end

  describe "PDF extraction — strict AMOUNT_RE" do
    it "matches comma-grouped Indian money (HDFC / ICICI style)" do
      ["1,000", "1,000.00", "1,00,000", "1,00,000.00", "12,34,567.89"].each do |sample|
        expect(sample).to match(StatementParsing::RegexExtractor::AMOUNT_RE)
      end
    end

    it "matches non-comma decimal money (Axis style)" do
      ["350.00", "0.50", "200000.00", "275676.93"].each do |sample|
        expect(sample).to match(StatementParsing::RegexExtractor::AMOUNT_RE)
      end
    end

    it "rejects bare integers (branch codes, reference numbers, account IDs)" do
      ["1955", "2567", "133826853", "917010081786930", "0001"].each do |sample|
        expect(sample).not_to match(StatementParsing::RegexExtractor::AMOUNT_RE)
      end
    end
  end

  it "returns [] for unknown formats" do
    expect(described_class.new(content: "...", format: :docx).call).to eq([])
  end
end
