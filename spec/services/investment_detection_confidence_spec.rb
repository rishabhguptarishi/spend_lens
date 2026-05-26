# frozen_string_literal: true

require "rails_helper"

# Phase 4 §5.7: InvestmentDetectionService now stamps a confidence score
# on every suggestion it creates. Verifies the tiered scoring rules from
# #score_match.
RSpec.describe InvestmentDetectionService, "confidence scoring" do
  let(:user) { make_user }
  let(:bank) { make_bank_account(user: user) }
  let(:statement) { make_statement(bank_account: bank, status: "parsed") }

  def make_bank_tx(description)
    make_transaction(statement: statement, description: description, amount: 5_000, transaction_type: "debit", date: Date.new(2026, 5, 1))
  end

  subject(:service) { described_class.new(user) }

  before { service.scan_transactions! }

  it "gives PPF-with-folio narrations 0.95 confidence (auto_resolved)" do
    make_bank_tx("Trf to PPF 000418336506")
    described_class.new(user).scan_transactions!
    s = InvestmentSuggestion.last
    expect(s.confidence.to_f).to be >= 0.9
    expect(s.match_bucket).to eq("auto_resolved")
    expect(s.metadata["folio_hint"]).to eq("000418336506")
  end

  it "gives MOB-TD with ref-number narrations 0.95 confidence" do
    make_bank_tx("MOB-TD/926040058278575/RISHABH GUPTA")
    described_class.new(user).scan_transactions!
    s = InvestmentSuggestion.last
    expect(s.confidence.to_f).to be >= 0.9
    expect(s.metadata["folio_hint"]).to eq("926040058278575")
  end

  it "gives FRSB-style narrations (named bond, no folio) ≥0.8 confidence" do
    make_bank_tx("FRSB/917010081786930/RISHABH GUPTA")
    described_class.new(user).scan_transactions!
    s = InvestmentSuggestion.last
    expect(s.confidence.to_f).to be >= 0.8
  end

  it "gives named-broker narrations 0.80 confidence (likely_match)" do
    make_bank_tx("ZERODHA BROKING")
    described_class.new(user).scan_transactions!
    s = InvestmentSuggestion.last
    expect(s.confidence.to_f).to eq(0.80)
    expect(s.match_bucket).to eq("likely_match")
  end

  it "gives generic registrar narrations 0.60 confidence (likely_match)" do
    make_bank_tx("CAMS RESPONSE FOR SIP")
    described_class.new(user).scan_transactions!
    s = InvestmentSuggestion.last
    expect(s.confidence.to_f).to eq(0.60)
    expect(s.match_bucket).to eq("likely_match")
  end
end
