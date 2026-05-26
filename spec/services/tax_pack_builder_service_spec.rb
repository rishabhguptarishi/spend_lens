# frozen_string_literal: true

require "rails_helper"
require "zip"

RSpec.describe TaxPackBuilderService, type: :service do
  let(:user) { make_user }
  subject(:service) { described_class.new(user, financial_year_start: 2026) }

  it "returns a binary ZIP string" do
    result = service.call
    expect(result).to be_a(String)
    expect(result[0, 2].bytes).to eq([0x50, 0x4B]) # "PK" signature
  end

  it "contains the expected 7 entries in the ZIP" do
    zip = service.call
    entries = []
    Zip::InputStream.open(StringIO.new(zip)) do |io|
      while (entry = io.get_next_entry)
        entries << entry.name
      end
    end

    expect(entries).to contain_exactly(
      "README.txt",
      "income_expense_summary.csv",
      "investment_fy_summary.csv",
      "capital_gains.csv",
      "ais_reconciliation.csv",
      "regime_comparison.csv",
      "filing_guide.txt"
    )
  end

  it "writes the FY label into README.txt and filing_guide.txt" do
    zip = service.call
    fy_label = FinancialYear.label(2026)

    readme = entry_for(zip, "README.txt")
    expect(readme).to include(fy_label)

    guide = entry_for(zip, "filing_guide.txt")
    expect(guide).to include(fy_label)
  end

  it "regression: capital_gains.csv produces a real CSV (was a Hash#to_csv NoMethodError previously)" do
    zip = service.call
    csv = entry_for(zip, "capital_gains.csv")
    expect(csv).to include("Capital gains summary")
  end

  def entry_for(zip_bytes, name)
    Zip::InputStream.open(StringIO.new(zip_bytes)) do |io|
      while (entry = io.get_next_entry)
        return io.read if entry.name == name
      end
    end
    nil
  end
end
