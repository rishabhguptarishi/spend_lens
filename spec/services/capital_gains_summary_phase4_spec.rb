# frozen_string_literal: true

require "rails_helper"

# Phase 4 additions to CapitalGainsSummaryService — supersession-aware
# totals, canonical-vs-heuristic figures, and source breakdown.
RSpec.describe CapitalGainsSummaryService, "Phase 4 unification" do
  let(:user) { make_user }
  let(:account) { make_investment_account(user: user) }
  let(:holding) do
    make_investment_holding(user: user, investment_account: account, name: "INFY", asset_class: "stock")
  end
  subject(:service) { described_class.new(user, financial_year_start: 2026) }

  describe "supersession-aware totals" do
    it "excludes superseded sells from canonical totals but surfaces them as audit" do
      legacy = user.investment_transactions.create!(
        date: Date.new(2026, 6, 1), kind: "sell", amount: 30_000, source: "broker_import",
        investment_holding: holding, asset_class: "stock",
      )
      authoritative = user.investment_transactions.create!(
        date: Date.new(2026, 6, 1), kind: "sell", amount: 30_000, source: "cdsl_cas",
        investment_holding: holding, asset_class: "stock",
      )
      legacy.update_columns(superseded_by_id: authoritative.id)

      result = service.call
      # Canonical = only active (non-superseded) — 1 row, ₹30k.
      expect(result[:rows].size).to eq(1)
      expect(result[:total_sell_amount]).to eq(30_000.0)
      expect(result[:superseded_sell_amount]).to eq(30_000.0)
      # Without supersession we'd see ₹60k — proves dedup works.
    end
  end

  describe "canonical_capital_gains" do
    it "uses tax-doc figures when present (canonical_source: tax_doc)" do
      doc = user.itr_tax_documents.create!(
        document_type: "broker_pl",
        financial_year_start: 2026,
        extraction_status: "extracted",
        extracted_data: { "stcg" => 25_000, "ltcg" => 100_000 },
      )
      doc.file.attach(io: StringIO.new("dummy"), filename: "broker.pdf", content_type: "application/pdf")

      user.investment_transactions.create!(
        date: Date.new(2026, 6, 1), kind: "sell", amount: 5_000, source: "broker_import",
        investment_holding: holding, asset_class: "stock",
      )

      result = service.call
      expect(result[:canonical_source]).to eq("tax_doc")
      expect(result[:canonical_stcg]).to eq(25_000.0)
      expect(result[:canonical_ltcg]).to eq(100_000.0)
    end

    it "falls back to heuristic when no tax docs are uploaded" do
      user.investment_transactions.create!(
        date: Date.new(2026, 6, 1), kind: "sell", amount: 5_000, source: "broker_import",
        investment_holding: holding, asset_class: "stock",
      )

      result = service.call
      expect(result[:canonical_source]).to eq("heuristic")
      expect(result[:canonical_stcg]).to eq(5_000.0)
      expect(result[:canonical_ltcg]).to eq(0.0)
    end
  end

  describe "source_breakdown" do
    it "counts canonical sells by source" do
      user.investment_transactions.create!(
        date: Date.new(2026, 6, 1), kind: "sell", amount: 5_000, source: "broker_import",
        investment_holding: holding, asset_class: "stock",
      )
      user.investment_transactions.create!(
        date: Date.new(2026, 7, 1), kind: "sell", amount: 10_000, source: "cdsl_cas",
        investment_holding: holding, asset_class: "stock",
      )

      result = service.call
      expect(result[:source_breakdown]).to eq("broker_import" => 1, "cdsl_cas" => 1)
    end
  end

  describe "REIT/InvIT classified as STCG by default" do
    it "treats reit sells as STCG (heuristic)" do
      reit = make_investment_holding(user: user, investment_account: account, name: "Embassy REIT", asset_class: "reit")
      user.investment_transactions.create!(
        date: Date.new(2026, 8, 1), kind: "sell", amount: 20_000, source: "broker_import",
        investment_holding: reit, asset_class: "reit",
      )
      result = service.call
      expect(result[:rows].first[:gain_type]).to eq("STCG")
    end
  end
end
