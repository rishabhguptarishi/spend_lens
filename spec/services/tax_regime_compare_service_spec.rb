# frozen_string_literal: true

require "rails_helper"

# Regression coverage for: ArgumentError (comparison of Integer with String)
# at tax_regime_compare_service.rb:35 when deduction params arrive as empty
# strings from the query (e.g. ?deduction_80c=&deduction_80d=&hra=).
RSpec.describe TaxRegimeCompareService, type: :service do
  let(:user) { User.create!(email: "tax-test@example.com", password: "password123") }
  let(:fy) { 2026 }

  # Stub ItrReadinessService so we don't need real bank-account fixtures.
  let(:readiness_stub) do
    {
      financial_year_start: fy,
      income: 1_500_000.0,
      expenses: 600_000.0,
      salary_estimate: 1_500_000.0,
    }
  end

  def call_service(deductions:)
    described_class.new(
      user,
      financial_year_start: fy,
      deductions: deductions,
      readiness: readiness_stub
    ).call
  end

  describe "the original bug — empty-string deduction params" do
    it "does NOT raise when all deductions arrive as empty strings" do
      expect {
        call_service(deductions: { deduction_80c: "", deduction_80d: "", hra: "" })
      }.not_to raise_error
    end

    it "does NOT raise when params are nil" do
      expect {
        call_service(deductions: { deduction_80c: nil, deduction_80d: nil, hra: nil })
      }.not_to raise_error
    end

    it "does NOT raise when params are whitespace-only" do
      expect {
        call_service(deductions: { deduction_80c: "   ", deduction_80d: "  ", hra: "\t" })
      }.not_to raise_error
    end

    it "treats blank deductions as zero" do
      result = call_service(deductions: { deduction_80c: "", deduction_80d: "", hra: "" })
      expect(result[:deductions_used]["80c"]).to eq(0.0)
      expect(result[:deductions_used]["80d"]).to eq(0.0)
      expect(result[:deductions_used]["hra"]).to eq(0.0)
    end
  end

  describe "deduction value handling" do
    it "accepts numeric strings" do
      result = call_service(deductions: { deduction_80c: "120000" })
      expect(result[:deductions_used]["80c"]).to eq(120_000.0)
    end

    it "accepts Float and Integer values directly" do
      result = call_service(deductions: { deduction_80c: 100_000, deduction_80d: 25_000.5 })
      expect(result[:deductions_used]["80c"]).to eq(100_000.0)
      expect(result[:deductions_used]["80d"]).to eq(25_000.5)
    end

    it "caps 80C at the statutory ₹1.5L limit even if user supplies more" do
      result = call_service(deductions: { deduction_80c: "500000" })
      expect(result[:deductions_used]["80c"]).to eq(150_000.0)
    end

    it "coerces non-numeric junk to 0.0 without crashing" do
      result = call_service(deductions: { deduction_80c: "abc" })
      expect(result[:deductions_used]["80c"]).to eq(0.0)
    end
  end

  describe "the tax computation" do
    it "returns the full comparison hash with both regimes" do
      result = call_service(deductions: {})

      expect(result).to include(
        :gross_income,
        :new_regime,
        :old_regime,
        :likely_better,
        :savings,
        :disclaimer
      )
      expect(result[:new_regime]).to include(:taxable, :tax, :cess, :total)
      expect(result[:old_regime]).to include(:taxable, :tax, :cess, :total)
    end

    it "applies the new-regime standard deduction (₹75,000)" do
      result = call_service(deductions: {})
      expected_taxable = 1_500_000.0 - TaxRegimeCompareService::STANDARD_DEDUCTION_NEW
      expect(result[:new_regime][:taxable]).to eq(expected_taxable)
    end

    it "applies the old-regime standard deduction (₹50,000) + user-provided deductions" do
      result = call_service(deductions: { deduction_80c: "150000", deduction_80d: "25000", hra: "100000" })
      expected_taxable = 1_500_000.0 - 50_000 - 150_000 - 25_000 - 100_000
      expect(result[:old_regime][:taxable]).to eq(expected_taxable)
    end

    it "picks the regime with the lower total tax as `likely_better`" do
      result = call_service(deductions: { deduction_80c: "150000", deduction_80d: "25000" })
      expect(%w[new old]).to include(result[:likely_better])
      expect(result[:savings]).to be >= 0
    end

    it "guards against negative taxable income" do
      low_income = readiness_stub.merge(income: 30_000.0)
      service = described_class.new(user, financial_year_start: fy, deductions: {}, readiness: low_income)
      result = service.call
      expect(result[:new_regime][:taxable]).to eq(0.0)
      expect(result[:old_regime][:taxable]).to eq(0.0)
    end
  end
end
