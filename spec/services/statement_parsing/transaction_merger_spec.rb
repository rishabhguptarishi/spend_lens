# frozen_string_literal: true

require "rails_helper"

RSpec.describe StatementParsing::TransactionMerger, type: :service do
  let(:date) { Date.new(2026, 4, 10) }

  def tx(overrides)
    { date: date, description: "Coffee", amount: 100.0, transaction_type: "debit", source: "regex" }.merge(overrides)
  end

  describe ".merge" do
    it "returns valid regex rows when AI list is empty" do
      regex = [tx({})]
      merged = described_class.merge(regex, [])
      expect(merged.size).to eq(1)
      expect(merged.first[:description]).to eq("Coffee")
    end

    it "dedupes by [date, amount rounded, description prefix]" do
      regex = [tx({})]
      ai    = [tx(source: "ai")]
      merged = described_class.merge(regex, ai)
      expect(merged.size).to eq(1)
      expect(merged.first[:source]).to eq("regex")
    end

    it "keeps AI-only rows alongside regex rows when not duplicates" do
      regex = [tx(description: "From regex", date: date)]
      ai    = [tx(description: "AI only entry", source: "ai", date: date + 1.day)]
      merged = described_class.merge(regex, ai)
      expect(merged.map { |t| t[:description] }).to include("From regex", "AI only entry")
    end

    it "drops the AI list entirely when trust_ai is false" do
      regex = [tx(description: "From regex")]
      ai    = [tx(description: "AI only", source: "ai", date: date + 1.day)]
      merged = described_class.merge(regex, ai, trust_ai: false)
      expect(merged.size).to eq(1)
      expect(merged.first[:description]).to eq("From regex")
    end

    it "sorts the result by date ascending, then amount descending" do
      rows = [
        tx(date: date + 1.day, amount: 100, description: "BB"),
        tx(date: date,         amount: 200, description: "A1"),
        tx(date: date,         amount: 100, description: "A2"),
      ]
      sorted = described_class.merge(rows, [])
      expect(sorted.map { |t| t[:description] }).to eq(["A1", "A2", "BB"])
    end
  end

  describe ".dedupe_key" do
    it "normalizes whitespace and case for the description portion" do
      a = tx(description: "  Some   Coffee  ")
      b = tx(description: "some coffee")
      expect(described_class.dedupe_key(a)).to eq(described_class.dedupe_key(b))
    end
  end
end
