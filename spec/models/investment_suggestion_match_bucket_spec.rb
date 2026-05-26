# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentSuggestion, "match_bucket" do
  let(:user) { make_user }
  let(:bank) { make_bank_account(user: user) }
  let(:statement) { make_statement(bank_account: bank, status: "parsed") }
  def fresh_tx(desc = "ZERODHA")
    make_transaction(statement: statement, description: "#{desc} #{rand(1_000_000)}", date: Date.new(2026, 4, 1))
  end

  def make(confidence, desc: "ZERODHA")
    InvestmentSuggestion.create!(
      user: user,
      source_transaction: fresh_tx(desc),
      suggested_asset_class: "stock",
      suggested_kind: "buy",
      status: "pending",
      confidence: confidence,
    )
  end

  it "buckets ≥0.9 as auto_resolved" do
    expect(make(0.95).match_bucket).to eq("auto_resolved")
    expect(make(0.9).reload.match_bucket).to eq("auto_resolved")
  end

  it "buckets 0.5..<0.9 as likely_match" do
    # Use a fresh transaction per call because suggestion is unique per tx.
    s = InvestmentSuggestion.new(user: user, source_transaction: make_transaction(statement: statement, description: "ICICI Pru #{rand(1000)}"),
                                 suggested_asset_class: "mutual_fund", suggested_kind: "sip", status: "pending", confidence: 0.6)
    s.save!
    expect(s.match_bucket).to eq("likely_match")
  end

  it "buckets <0.5 as unknown" do
    s = InvestmentSuggestion.new(user: user, source_transaction: make_transaction(statement: statement, description: "GENERIC INV #{rand(1000)}"),
                                 suggested_asset_class: "other", suggested_kind: "buy", status: "pending", confidence: 0.3)
    s.save!
    expect(s.match_bucket).to eq("unknown")
  end

  it "defaults to 0.5 confidence → likely_match when omitted" do
    s = InvestmentSuggestion.new(user: user, source_transaction: fresh_tx,
                                 suggested_asset_class: "stock", suggested_kind: "buy", status: "pending")
    s.save!
    expect(s.confidence.to_f).to eq(0.5)
    expect(s.match_bucket).to eq("likely_match")
  end

  it "rebuckets on confidence change" do
    s = make(0.4)
    expect(s.match_bucket).to eq("unknown")
    s.update!(confidence: 0.95)
    expect(s.reload.match_bucket).to eq("auto_resolved")
  end
end
