# frozen_string_literal: true

require "rails_helper"

RSpec.describe StatementParsing::TransactionValidator, type: :service do
  describe ".valid?" do
    let(:valid_tx) { { date: Date.today, description: "SWIGGY ORDER", amount: 350.0, transaction_type: "debit" } }

    it "accepts a well-formed transaction" do
      expect(described_class.valid?(valid_tx)).to be true
    end

    it "rejects amounts below MIN_AMOUNT" do
      expect(described_class.valid?(valid_tx.merge(amount: 0.001))).to be false
    end

    it "rejects amounts above MAX_AMOUNT" do
      expect(described_class.valid?(valid_tx.merge(amount: 99_000_000))).to be false
    end

    it "rejects descriptions shorter than 2 chars" do
      expect(described_class.valid?(valid_tx.merge(description: "x"))).to be false
    end

    it "rejects generic placeholder descriptions" do
      expect(described_class.valid?(valid_tx.merge(description: "transaction 1"))).to be false
      expect(described_class.valid?(valid_tx.merge(description: "Test Transaction"))).to be false
    end

    it "rejects dates >15 years in the past" do
      expect(described_class.valid?(valid_tx.merge(date: Date.today - 20.years))).to be false
    end

    it "rejects dates >7 days in the future" do
      expect(described_class.valid?(valid_tx.merge(date: Date.today + 30.days))).to be false
    end
  end

  describe ".normalize" do
    it "downcases-classifies via credit keywords (regardless of given type)" do
      result = described_class.normalize(date: Date.today, description: "SALARY APRIL 2026", amount: 100_000, transaction_type: "debit")
      expect(result[:transaction_type]).to eq("credit")
    end

    it "force-positives the amount" do
      result = described_class.normalize(date: Date.today, description: "Swiggy", amount: -350)
      expect(result[:amount]).to eq(350.0)
    end

    it "truncates descriptions over 200 chars" do
      long = "x" * 300
      result = described_class.normalize(date: Date.today, description: long, amount: 100)
      expect(result[:description].length).to eq(201)
    end

    it "parses dd/mm/yyyy date strings" do
      result = described_class.normalize(date: "10/04/2026", description: "X", amount: 1)
      expect(result[:date]).to eq(Date.new(2026, 4, 10))
    end
  end

  describe ".validate_all" do
    it "filters out invalid rows and normalizes valid ones" do
      rows = [
        { date: Date.today, description: "Valid", amount: 100, transaction_type: "debit" },
        { date: Date.today, description: "x", amount: 100 },
        { date: Date.today - 50.years, description: "Way in the past", amount: 100 },
      ]
      out = described_class.validate_all(rows)
      expect(out.size).to eq(1)
      expect(out.first[:description]).to eq("Valid")
    end
  end

  describe ".ai_batch_trustworthy?" do
    it "trusts an empty AI list" do
      expect(described_class.ai_batch_trustworthy?([], Array.new(50))).to be true
    end

    it "rejects an AI list that is too sparse compared to regex" do
      regex = Array.new(50) { { description: "x" } }
      ai = Array.new(2) { { description: "y" } }
      expect(described_class.ai_batch_trustworthy?(ai, regex)).to be false
    end

    it "rejects an AI list that is ≥ 50% generic placeholders" do
      ai = Array.new(10) { |i| { description: i.even? ? "transaction #{i}" : "real desc #{i}" } }
      expect(described_class.ai_batch_trustworthy?(ai, [])).to be false
    end

    it "trusts a healthy AI list" do
      ai = Array.new(10) { |i| { description: "real desc #{i}" } }
      expect(described_class.ai_batch_trustworthy?(ai, [])).to be true
    end
  end
end
