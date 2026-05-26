# frozen_string_literal: true

require "rails_helper"

# Phase 6 §G13: detection cutoff is now per-user via UserPreference.
RSpec.describe InvestmentDetectionService, "lookback cutoff (Phase 6 §G13)" do
  let(:user) { make_user }
  let(:bank) { make_bank_account(user: user) }
  let(:statement) { make_statement(bank_account: bank, status: "parsed") }

  def tx_at(date, description: "ZERODHA")
    make_transaction(statement: statement, description: description, date: date)
  end

  it "honors the per-user investment_detect_lookback_months preference (3 months)" do
    user.user_preference.update!(investment_detect_lookback_months: 3)

    tx_at(2.months.ago.to_date)
    tx_at(6.months.ago.to_date)

    described_class.new(user).scan_transactions!
    suggestions = InvestmentSuggestion.where(user: user)
    expect(suggestions.size).to eq(1)
  end

  it "clamps invalid lookback values to default (24) — 0 months becomes 24" do
    user.user_preference.update!(investment_detect_lookback_months: 0)
    expect(user.user_preference.investment_detect_lookback_months).to eq(24)
  end

  it "clamps very large values to default (>120 becomes 24)" do
    user.user_preference.update!(investment_detect_lookback_months: 9999)
    expect(user.user_preference.investment_detect_lookback_months).to eq(24)
  end

  it "uses the default 24 months when never configured" do
    tx_at(12.months.ago.to_date)
    tx_at(30.months.ago.to_date)

    described_class.new(user).scan_transactions!
    expect(InvestmentSuggestion.where(user: user).size).to eq(1)
  end
end
