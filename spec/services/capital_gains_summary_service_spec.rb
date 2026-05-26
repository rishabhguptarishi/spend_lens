# frozen_string_literal: true

require "rails_helper"

RSpec.describe CapitalGainsSummaryService, type: :service do
  let(:user) { make_user }
  let(:account) { make_investment_account(user: user) }
  let(:holding) { make_investment_holding(user: user, investment_account: account, name: "INFY", asset_class: "stock") }
  subject(:service) { described_class.new(user, financial_year_start: 2026) }

  describe "#call" do
    it "returns zero totals when there are no sells" do
      result = service.call
      expect(result[:rows]).to eq([])
      expect(result[:total_sell_amount]).to eq(0.0)
      expect(result[:total_buy_amount]).to eq(0.0)
    end

    it "rolls up sells into STCG/LTCG/Review buckets by asset_class" do
      # Stock sell → STCG
      user.investment_transactions.create!(
        date: Date.new(2026, 6, 1), kind: "sell", amount: 30_000, source: "manual",
        investment_holding: holding, asset_class: "stock"
      )
      # Real estate sell → LTCG
      user.investment_transactions.create!(
        date: Date.new(2026, 7, 1), kind: "sell", amount: 1_000_000, source: "manual",
        asset_class: "real_estate"
      )
      # Crypto sell → Review
      user.investment_transactions.create!(
        date: Date.new(2026, 8, 1), kind: "sell", amount: 5_000, source: "manual",
        asset_class: "crypto"
      )

      result = service.call
      expect(result[:rows].size).to eq(3)
      expect(result[:rows].map { |r| r[:gain_type] }).to contain_exactly("STCG", "LTCG", "Review")
      expect(result[:estimated_stcg]).to eq(30_000.0)
      expect(result[:estimated_ltcg]).to eq(1_000_000.0)
      expect(result[:total_sell_amount]).to eq(1_035_000.0)
    end

    it "adds document_stcg / document_ltcg from extracted broker_pl docs" do
      doc = user.itr_tax_documents.create!(
        document_type: "broker_pl",
        financial_year_start: 2026,
        extraction_status: "extracted",
        extracted_data: { "stcg" => 25_000, "ltcg" => 100_000 }
      )
      doc.file.attach(io: StringIO.new("dummy"), filename: "broker.pdf", content_type: "application/pdf")

      result = service.call
      expect(result[:document_stcg]).to eq(25_000.0)
      expect(result[:document_ltcg]).to eq(100_000.0)
      expect(result[:from_tax_documents]).to include(ItrTaxDocument.label_for("broker_pl"))
    end
  end

  describe "#to_csv" do
    it "produces CSV with header and total rows" do
      user.investment_transactions.create!(
        date: Date.new(2026, 6, 1), kind: "sell", amount: 30_000, source: "manual",
        investment_holding: holding, asset_class: "stock"
      )
      csv = service.to_csv
      expect(csv).to include("Capital gains summary")
      # Phase 4: header was renamed to make clear we're showing canonical
      # (active, non-superseded) sells, with the superseded total
      # surfaced separately for audit.
      expect(csv).to include("Canonical total sells (active)")
      expect(csv).to include("Superseded total sells (audit)")
      expect(csv).to include("Est. STCG")
    end
  end
end
