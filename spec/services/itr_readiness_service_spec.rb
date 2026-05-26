# frozen_string_literal: true

require "rails_helper"

RSpec.describe ItrReadinessService, type: :service do
  let(:user) { make_user }
  let(:bank) { make_bank_account(user: user) }
  let(:statement) { make_statement(bank_account: bank, month: 4, year: 2026) }
  subject(:service) { described_class.new(user, financial_year_start: 2026) }

  describe "with no data" do
    it "returns a zero-income readiness summary suggesting ITR-1 as fallback" do
      result = service.call
      expect(result[:income]).to eq(0.0)
      expect(result[:expenses]).to eq(0.0)
      expect(result[:suggested_itr_form][:form]).to eq("ITR-1")
      expect(result[:data_source]).to eq("generated")
      expect(result[:readiness_pct]).to be_an(Integer)
    end
  end

  describe "with bank transactions" do
    before do
      make_transaction(statement: statement, date: Date.new(2026, 5, 1), description: "SALARY APRIL", amount: 100_000, transaction_type: "credit")
      make_transaction(statement: statement, date: Date.new(2026, 5, 2), description: "RENT", amount: 30_000, transaction_type: "debit")
    end

    it "computes income, expenses, salary and net" do
      result = service.call
      expect(result[:income]).to eq(100_000.0)
      expect(result[:expenses]).to eq(30_000.0)
      expect(result[:salary_estimate]).to eq(100_000.0)
      expect(result[:net]).to eq(70_000.0)
    end

    it "suggests ITR-1 for plain salary income" do
      expect(service.call[:suggested_itr_form][:form]).to eq("ITR-1")
    end

    it "marks the statements checklist item as done" do
      stmt_item = service.call[:checklist].find { |i| i[:id] == "statements" }
      expect(stmt_item[:done]).to be true
    end
  end

  describe "with realized capital gains (sell / transfer_out / maturity)" do
    before do
      user.investment_transactions.create!(date: Date.new(2026, 5, 1), kind: "sell", amount: 50_000, source: "manual")
    end

    it "suggests ITR-2 with a precise 'realized gains' reason" do
      form = service.call[:suggested_itr_form]
      expect(form[:form]).to eq("ITR-2")
      expect(form[:reason]).to include("Realized capital gains")
    end

    it "reports has_capital_gains_events as true (new accurate field)" do
      expect(service.call[:investment_summary][:has_capital_gains_events]).to be true
    end

    it "keeps has_capital_activity as a backward-compatible alias" do
      expect(service.call[:investment_summary][:has_capital_activity]).to be true
    end
  end

  describe "with only buy-side investment activity (regression for the 'ghost capital gains' bug)" do
    # Before the fix, importing a single SIP/buy/MOB-TD flipped
    # has_capital_activity to true → AI confidently said "file ITR-2
    # because of capital gains activity" → then admitted "actually I see
    # no capital gains". Buying alone never realizes a P&L.
    before do
      user.investment_transactions.create!(date: Date.new(2026, 5, 1), kind: "buy", amount: 50_000, source: "manual")
      user.investment_transactions.create!(date: Date.new(2026, 5, 2), kind: "sip", amount: 1_000, source: "manual")
      user.investment_transactions.create!(date: Date.new(2026, 5, 3), kind: "contribution", amount: 1_500, source: "manual")
      user.investment_transactions.create!(date: Date.new(2026, 5, 4), kind: "transfer_in", amount: 25_000, source: "manual")
    end

    it "does NOT suggest ITR-2 since no gains were realized" do
      form = service.call[:suggested_itr_form]
      expect(form[:form]).to eq("ITR-1")
      expect(form[:reason]).not_to include("capital gains")
    end

    it "reports has_capital_gains_events as false" do
      expect(service.call[:investment_summary][:has_capital_gains_events]).to be false
    end

    it "still counts the contributions for reporting" do
      summary = service.call[:investment_summary]
      expect(summary[:contributions]).to eq(77_500.0)
      expect(summary[:sells]).to eq(0.0)
    end
  end

  describe "with income above the ₹50 lakh ITR-1 cap" do
    before do
      make_transaction(statement: statement, date: Date.new(2026, 4, 1), description: "BONUS", amount: 60_00_000, transaction_type: "credit")
    end

    it "suggests ITR-2 citing the income threshold (not capital gains)" do
      form = service.call[:suggested_itr_form]
      expect(form[:form]).to eq("ITR-2")
      expect(form[:reason]).to include("above ₹50 lakh")
      expect(form[:reason]).not_to include("capital gains")
    end
  end

  describe "form-specific checklists" do
    it "shows business + balance-sheet items only when ITR-3 / ITR-4 is suggested" do
      # ITR-1 path → no business prompts
      make_transaction(statement: statement, date: Date.new(2026, 5, 1), description: "SALARY APRIL", amount: 1_000, transaction_type: "credit")
      ids = service.call[:checklist].map { |c| c[:id] }
      expect(ids).not_to include("business_pl", "balance_sheet", "tax_audit")

      # Switch to an ITR-3 scenario by adding business credits
      make_transaction(statement: statement, date: Date.new(2026, 5, 2), description: "CONSULTING INVOICE 42", amount: 200_000, transaction_type: "credit")
      itr3_ids = service.call[:checklist].map { |c| c[:id] }
      expect(itr3_ids).to include("business_pl", "balance_sheet")
    end

    it "shows depository / broker CG items only on ITR-2 / ITR-3" do
      user.investment_transactions.create!(date: Date.new(2026, 5, 1), kind: "sell", amount: 50_000, source: "manual")
      ids = service.call[:checklist].map { |c| c[:id] }
      expect(ids).to include("broker_pl", "mf_cg", "cas")
    end
  end

  describe "deduction aggregation across multiple receipts" do
    before do
      # Two LIC receipts + one ELSS — all eligible under 80C
      user.itr_tax_documents.create!(document_type: "lic_premium", financial_year_start: 2026,
                                     extracted_data: { "premium_paid" => 30_000 })
      user.itr_tax_documents.create!(document_type: "lic_premium", financial_year_start: 2026,
                                     extracted_data: { "premium_paid" => 40_000 }, payer_name: "LIC #2")
      user.itr_tax_documents.create!(document_type: "elss_80c", financial_year_start: 2026,
                                     extracted_data: { "amount_invested" => 50_000 })
      # 80D health insurance
      user.itr_tax_documents.create!(document_type: "health_insurance_80d", financial_year_start: 2026,
                                     extracted_data: { "premium_paid" => 18_000 })
    end

    it "sums all instances per section, capped at the statutory limit" do
      ded = service.call[:deductions]
      expect(ded["80C"][:raw_total]).to eq(120_000.0)
      expect(ded["80C"][:used]).to eq(120_000.0) # under the ₹1.5L cap
      expect(ded["80C"][:remaining]).to eq(30_000.0)
      expect(ded["80C"][:utilisation_pct]).to eq(80.0)

      expect(ded["80D"][:used]).to eq(18_000.0)
    end

    it "caps over-contributions at the section limit" do
      user.itr_tax_documents.create!(document_type: "ppf_80c", financial_year_start: 2026,
                                     extracted_data: { "contributions_in_fy" => 150_000 })
      ded = service.call[:deductions]
      expect(ded["80C"][:raw_total]).to eq(270_000.0) # 120k + 150k
      expect(ded["80C"][:used]).to eq(150_000.0)     # capped at 1.5L
      expect(ded["80C"][:remaining]).to eq(0.0)
    end
  end

  describe "document inventory" do
    it "lists every registry doc type with multi-instance support" do
      user.itr_tax_documents.create!(document_type: "form16a", financial_year_start: 2026, payer_name: "HDFC")
      user.itr_tax_documents.create!(document_type: "form16a", financial_year_start: 2026, payer_name: "ICICI")
      inv = service.call[:documents]
      expect(inv["form16a"][:count]).to eq(2)
      expect(inv["form16a"][:instances].map { |i| i[:payer_name] }).to contain_exactly("HDFC", "ICICI")
      expect(inv["form16a"][:multiple_per_fy]).to be true

      expect(inv["broker_pl"][:uploaded]).to be false
      expect(inv["broker_pl"][:count]).to eq(0)
    end
  end

  describe "with a Form 16 uploaded" do
    let!(:form16) do
      user.itr_tax_documents.create!(document_type: "form16", financial_year_start: 2026, extraction_status: "extracted")
        .tap { |d| d.file.attach(io: StringIO.new("dummy"), filename: "form16.pdf", content_type: "application/pdf") }
    end

    it "marks data_source as 'mixed'" do
      expect(service.call[:data_source]).to eq("mixed")
    end

    it "marks the form16 checklist item as done" do
      f16 = service.call[:checklist].find { |i| i[:id] == "form16" }
      expect(f16[:done]).to be true
    end
  end
end
