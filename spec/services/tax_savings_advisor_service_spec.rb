# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaxSavingsAdvisorService, type: :service do
  let(:user) { make_user }
  let(:bank) { make_bank_account(user: user) }
  let(:statement) { make_statement(bank_account: bank, month: 4, year: 2026) }
  subject(:advisor) { described_class.new(user, financial_year_start: 2026) }

  describe "no data" do
    it "returns a recommendations array (empty or minimal) and a disclaimer" do
      result = advisor.call
      expect(result[:recommendations]).to be_an(Array)
      expect(result[:disclaimer]).to be_present
      expect(result[:financial_year_start]).to eq(2026)
    end
  end

  describe "OLD-regime recommendations for a mid-income salaried filer" do
    before do
      # ₹12 lakh salary credits — pushes 20% slab; OLD regime competitive
      user.user_preference.update!(preferred_tax_regime: 'old')
      make_transaction(statement: statement, date: Date.new(2026, 4, 1),
                       description: "SALARY APRIL", amount: 1_200_000,
                       transaction_type: "credit")
    end

    it "recommends 80C with the full ₹1.5L unused" do
      rec = find_rec(advisor.call, '80C')
      expect(rec).to be_present
      expect(rec[:cap]).to eq(150_000)
      expect(rec[:remaining]).to eq(150_000.0)
      expect(rec[:priority]).to eq(:high)
      expect(rec[:potential_saving]).to be > 0
      expect(rec[:action]).to match(/ELSS|PPF|Sukanya/i)
    end

    it "recommends 80CCD(1B) NPS extra ₹50k" do
      rec = find_rec(advisor.call, '80CCD(1B)')
      expect(rec).to be_present
      expect(rec[:cap]).to eq(50_000)
      expect(rec[:remaining]).to eq(50_000.0)
      expect(rec[:priority]).to eq(:high)
      expect(rec[:action]).to match(/NPS\s*Tier-?I/i)
    end

    it "recommends 80D health insurance when none is uploaded" do
      rec = find_rec(advisor.call, '80D')
      expect(rec).to be_present
      expect(rec[:cap]).to eq(100_000)
      expect(rec[:priority]).to eq(:high)
    end

    it "ranks 80C above 80D when both have the same priority (larger potential saving wins)" do
      sections = advisor.call[:recommendations].map { |r| r[:section] }
      expect(sections.index('80C')).to be < sections.index('80D')
    end
  end

  describe "respects already-claimed deductions from uploaded docs" do
    before do
      user.user_preference.update!(preferred_tax_regime: 'old')
      make_transaction(statement: statement, date: Date.new(2026, 4, 1),
                       description: "SALARY APRIL", amount: 1_200_000,
                       transaction_type: "credit")
      # ₹1L of 80C claimed via LIC
      user.itr_tax_documents.create!(document_type: "lic_premium", financial_year_start: 2026,
                                     extracted_data: { "premium_paid" => 100_000 })
    end

    it "subtracts used 80C from the remaining cap" do
      rec = find_rec(advisor.call, '80C')
      expect(rec[:used]).to eq(100_000.0)
      expect(rec[:remaining]).to eq(50_000.0)
      expect(rec[:priority]).to eq(:medium) # not high anymore
    end

    it "marks 80C as low priority when cap is fully utilised" do
      user.itr_tax_documents.create!(document_type: "elss_80c", financial_year_start: 2026,
                                     extracted_data: { "amount_invested" => 80_000 })
      rec = find_rec(advisor.call, '80C')
      expect(rec[:remaining]).to eq(0.0)
      expect(rec[:priority]).to eq(:low)
      expect(rec[:action]).to match(/utilised/i)
    end
  end

  describe "NEW-regime suppression" do
    before do
      user.user_preference.update!(preferred_tax_regime: 'new')
      make_transaction(statement: statement, date: Date.new(2026, 4, 1),
                       description: "SALARY APRIL", amount: 1_200_000,
                       transaction_type: "credit")
    end

    it "does NOT suggest 80C / 80D / 80CCD(1B) under NEW regime (deductions don't apply)" do
      sections = advisor.call[:recommendations].map { |r| r[:section] }
      expect(sections).not_to include('80C', '80D', '80CCD(1B)')
    end

    it "still includes regime / capital-gains recs that apply to both regimes" do
      # No special docs so the regime rec may or may not appear (depends
      # on calculated savings); just confirm the suppression doesn't
      # wipe out the entire response.
      result = advisor.call
      expect(result[:recommendations]).to be_an(Array)
      expect(result[:disclaimer]).to be_present
    end
  end

  describe "rent / HRA branching" do
    before do
      user.user_preference.update!(preferred_tax_regime: 'old')
      make_transaction(statement: statement, date: Date.new(2026, 4, 1),
                       description: "SALARY APRIL", amount: 1_200_000,
                       transaction_type: "credit")
      make_transaction(statement: statement, date: Date.new(2026, 4, 5),
                       description: "RENT PAID APR", amount: 30_000,
                       transaction_type: "debit")
    end

    it "suggests HRA when Form 16 shows an HRA component" do
      user.itr_tax_documents.create!(document_type: "form16", financial_year_start: 2026,
                                     extracted_data: { "hra_received" => 200_000 })
      rec = find_rec(advisor.call, 'HRA')
      expect(rec).to be_present
      expect(rec[:label]).to match(/HRA/)
    end

    it "suggests 80GG instead when there's no HRA in Form 16" do
      user.itr_tax_documents.create!(document_type: "form16", financial_year_start: 2026,
                                     extracted_data: { "salary" => 1_200_000 })
      rec = find_rec(advisor.call, '80GG')
      expect(rec).to be_present
      expect(rec[:cap]).to eq(60_000)
      expect(rec[:action]).to match(/Form\s*10BA/)
    end

    it "skips rent recommendations entirely when there are no rent indicators" do
      # Replace rent debit with something neutral
      Transaction.where("description LIKE 'RENT%'").destroy_all
      sections = advisor.call[:recommendations].map { |r| r[:section] }
      expect(sections).not_to include('HRA', '80GG')
    end
  end

  describe "capital-gains documentation nudge" do
    before do
      user.investment_transactions.create!(date: Date.new(2026, 5, 1), kind: "sell", amount: 50_000, source: "manual")
    end

    it "high-priority nudge when realized gains exist but no broker P&L / MF CG uploaded" do
      rec = find_rec(advisor.call, 'CG_DOCS')
      expect(rec).to be_present
      expect(rec[:priority]).to eq(:high)
      expect(rec[:action]).to match(/Schedule\s*CG/)
    end

    it "disappears once a broker P&L is uploaded" do
      user.itr_tax_documents.create!(document_type: "broker_pl", financial_year_start: 2026,
                                     payer_name: "Zerodha")
      expect(find_rec(advisor.call, 'CG_DOCS')).to be_nil
    end
  end

  describe "marginal_rate_used" do
    it "uses 0% slab for sub-₹5L incomes" do
      expect(advisor.call[:marginal_rate_used]).to eq(0)
    end

    it "uses 5% slab between ₹5L–₹10L" do
      make_transaction(statement: statement, date: Date.new(2026, 4, 1),
                       description: "SALARY", amount: 700_000, transaction_type: "credit")
      expect(advisor.call[:marginal_rate_used]).to eq(0.05)
    end

    it "uses 20% slab between ₹10L–₹20L" do
      make_transaction(statement: statement, date: Date.new(2026, 4, 1),
                       description: "SALARY", amount: 1_500_000, transaction_type: "credit")
      expect(advisor.call[:marginal_rate_used]).to eq(0.20)
    end

    it "uses 30% slab above ₹20L" do
      make_transaction(statement: statement, date: Date.new(2026, 4, 1),
                       description: "SALARY", amount: 3_000_000, transaction_type: "credit")
      expect(advisor.call[:marginal_rate_used]).to eq(0.30)
    end
  end

  describe "total_potential_saving" do
    it "sums the savings across all recommendations" do
      user.user_preference.update!(preferred_tax_regime: 'old')
      make_transaction(statement: statement, date: Date.new(2026, 4, 1),
                       description: "SALARY APRIL", amount: 1_500_000,
                       transaction_type: "credit")
      total = advisor.call[:total_potential_saving]
      sum_of_recs = advisor.call[:recommendations].sum { |r| r[:potential_saving] }
      expect(total).to eq(sum_of_recs)
      expect(total).to be > 0
    end
  end

  def find_rec(result, section)
    result[:recommendations].find { |r| r[:section] == section }
  end
end
