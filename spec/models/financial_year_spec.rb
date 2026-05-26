# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinancialYear, type: :model do
  describe ".start_year_for" do
    it "returns the same year for dates on/after April 1" do
      expect(described_class.start_year_for(Date.new(2026, 4, 1))).to eq(2026)
      expect(described_class.start_year_for(Date.new(2026, 12, 31))).to eq(2026)
    end

    it "returns the previous year for dates before April 1" do
      expect(described_class.start_year_for(Date.new(2026, 1, 15))).to eq(2025)
      expect(described_class.start_year_for(Date.new(2026, 3, 31))).to eq(2025)
    end
  end

  describe ".range_for" do
    it "returns the April 1 → March 31 range for the given start year" do
      range = described_class.range_for(2026)
      expect(range.first).to eq(Date.new(2026, 4, 1))
      expect(range.last).to eq(Date.new(2027, 3, 31))
    end
  end

  describe ".label" do
    it "formats FY label as 'YYYY-YY'" do
      expect(described_class.label(2026)).to eq("2026-27")
      expect(described_class.label(2024)).to eq("2024-25")
    end
  end

  describe ".current_start_year" do
    it "returns a Numeric year" do
      expect(described_class.current_start_year).to be_a(Integer)
    end
  end

  describe ".available_years" do
    it "returns 10 years by default, most recent first" do
      years = described_class.available_years
      expect(years.size).to eq(10)
      expect(years).to eq(years.sort.reverse)
    end

    it "respects the count keyword" do
      expect(described_class.available_years(count: 3).size).to eq(3)
    end
  end
end
