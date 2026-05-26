# frozen_string_literal: true

require "rails_helper"

RSpec.describe ItrFySnapshot, type: :service do
  let(:user) { make_user }
  subject(:snapshot) { described_class.new(user, financial_year_start: 2026) }

  describe "lazy-memoized aggregates" do
    it "delegates #readiness to ItrReadinessService and memoizes" do
      expect(ItrReadinessService).to receive(:new).once.and_call_original
      snapshot.readiness
      snapshot.readiness
    end

    it "delegates #reconciliation to AisReconciliationService (passing readiness through)" do
      expect(AisReconciliationService).to receive(:new)
        .with(user, financial_year_start: 2026, readiness: kind_of(Hash))
        .and_call_original
      snapshot.reconciliation
    end

    it "delegates #regime_compare to TaxRegimeCompareService" do
      expect(TaxRegimeCompareService).to receive(:new).and_call_original
      snapshot.regime_compare
    end

    it "delegates #capital_gains to CapitalGainsSummaryService and returns the Hash result" do
      expect(CapitalGainsSummaryService).to receive(:new).and_call_original
      result = snapshot.capital_gains
      expect(result).to be_a(Hash)
      expect(result).to include(:rows, :financial_year_start)
    end
  end

  it "exposes user / fy / range attrs" do
    expect(snapshot.user).to eq(user)
    expect(snapshot.fy).to eq(2026)
    expect(snapshot.range.first).to eq(Date.new(2026, 4, 1))
  end
end
