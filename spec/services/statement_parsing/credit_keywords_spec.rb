# frozen_string_literal: true

require "rails_helper"

# Regression coverage for the NameError + NoMethodError we hit in production
# logs when uploading a credit-card statement. Both errors stemmed from the
# StatementParsing module living in a file Zeitwerk couldn't autoload.
RSpec.describe StatementParsing::CreditKeywords, type: :service do
  describe ".match?" do
    it "matches strings containing SALARY (canonical credit signal)" do
      expect(described_class.match?("SALARY CREDIT - ACME CORP")).to be true
    end

    it "matches case-insensitively" do
      expect(described_class.match?("salary credit")).to be true
      expect(described_class.match?("SaLaRy")).to be true
    end

    it "matches other known credit keywords" do
      %w[CRV CREDIT REFUND REVERSAL INTEREST DEPOSIT].each do |kw|
        expect(described_class.match?("Some #{kw} entry")).to be(true), "expected '#{kw}' to match"
      end
    end

    it "matches compound patterns like NEFT CR and RTGS CR" do
      expect(described_class.match?("NEFT CR 12345 ABC LTD")).to be true
      expect(described_class.match?("RTGS CR FROM XYZ")).to be true
    end

    it "matches the quirky 'A AINT' pattern (real-world bank shorthand)" do
      expect(described_class.match?("A AINT TRANSFER")).to be true
    end

    it "does not match generic debit descriptions" do
      %w[SWIGGY ZOMATO AMAZON UBER FUEL].each do |kw|
        expect(described_class.match?(kw)).to be(false), "expected '#{kw}' NOT to match"
      end
    end

    it "is safe with nil input" do
      expect(described_class.match?(nil)).to be false
    end

    it "is safe with non-string input" do
      expect(described_class.match?(12345)).to be false
      expect(described_class.match?(Object.new)).to be false
    end
  end

  describe "REGEX constant" do
    it "exposes the underlying regex for direct use" do
      expect(described_class::REGEX).to be_a(Regexp)
    end
  end
end

RSpec.describe StatementParsing, type: :service do
  describe ".credit?" do
    it "is the public delegate used across the parsing pipeline" do
      expect(described_class).to respond_to(:credit?)
    end

    it "delegates to CreditKeywords.match?" do
      expect(StatementParsing::CreditKeywords).to receive(:match?).with("X").and_return(true)
      expect(described_class.credit?("X")).to be true
    end

    it "behaves identically to CreditKeywords.match? for real inputs" do
      ["SALARY ABC", "REFUND ORDER", "SWIGGY", nil, ""].each do |input|
        expect(described_class.credit?(input)).to eq(StatementParsing::CreditKeywords.match?(input)),
          "mismatch for input: #{input.inspect}"
      end
    end
  end
end
