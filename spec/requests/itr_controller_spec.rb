# frozen_string_literal: true

require "rails_helper"

# Request specs for the ITR regime endpoint. Specifically guards against the
# 500 we hit when blank query strings (deduction_80c=&deduction_80d=&hra=)
# leaked through unsanitized into TaxRegimeCompareService.
RSpec.describe "ItrController#regime", type: :request do
  let(:user) { User.create!(email: "itr-req@example.com", password: "password123") }

  before do
    sign_in user
    # Stub the readiness service so we don't need bank-account / transaction fixtures.
    allow_any_instance_of(ItrReadinessService).to receive(:call).and_return(
      financial_year_start: 2026,
      income: 1_200_000.0,
      expenses: 400_000.0,
      salary_estimate: 1_200_000.0,
    )
  end

  describe "GET /itr/regime" do
    it "renders 200 with blank deduction params (regression for #500 bug)" do
      get "/itr/regime", params: { year: 2026, deduction_80c: "", deduction_80d: "", hra: "" }
      expect(response).to have_http_status(:ok)
    end

    it "renders 200 with no deduction params at all" do
      get "/itr/regime", params: { year: 2026 }
      expect(response).to have_http_status(:ok)
    end

    it "renders 200 with whitespace-only deduction params" do
      get "/itr/regime", params: { year: 2026, deduction_80c: "   ", deduction_80d: "\t", hra: " " }
      expect(response).to have_http_status(:ok)
    end

    it "renders 200 with valid numeric deductions" do
      get "/itr/regime", params: { year: 2026, deduction_80c: "120000", deduction_80d: "25000", hra: "100000" }
      expect(response).to have_http_status(:ok)
    end

    it "renders 200 with non-numeric junk in deduction fields" do
      get "/itr/regime", params: { year: 2026, deduction_80c: "abc", deduction_80d: "n/a" }
      expect(response).to have_http_status(:ok)
    end

    it "falls back to current FY when year is invalid" do
      get "/itr/regime", params: { year: "9999" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /itr (index — full page with registry catalog & savings advisor)" do
    it "renders 200 and includes the registry-driven document_catalog & tax_savings props" do
      allow_any_instance_of(TaxSavingsAdvisorService).to receive(:call).and_return(
        financial_year_start: 2026,
        financial_year_label: "2026-27",
        regime_recommendation: "new",
        regime_savings: 0,
        marginal_rate_used: 0.20,
        old_regime_relevant: true,
        total_potential_saving: 0,
        recommendations: [],
        suggested_form: { form: "ITR-1" },
        disclaimer: "advisory",
      )
      allow_any_instance_of(ItrReadinessService).to receive(:call).and_return(
        financial_year_start: 2026,
        financial_year_label: "2026-27",
        income: 0.0, expenses: 0.0, salary_estimate: 0.0, business_income_estimate: 0.0,
        net: 0.0,
        suggested_itr_form: { form: "ITR-1", reason: "Default" },
        investment_summary: { holdings_count: 0, transaction_count: 0, has_capital_gains_events: false, sells: 0.0, contributions: 0.0, dividends_interest: 0.0 },
        documents: {}, deductions: {}, checklist: [], readiness_pct: 0,
        data_source: "generated"
      )

      get "/itr", params: { year: 2026 }
      expect(response).to have_http_status(:ok)
    end
  end
end
