# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentImportBatch, type: :model do
  let(:user) { make_user }

  describe "validations" do
    it "requires financial_year_start" do
      batch = user.investment_import_batches.new(source: "zerodha", status: "preview")
      expect(batch).not_to be_valid
    end

    it "rejects unknown sources" do
      expect(user.investment_import_batches.new(source: "bogus", status: "preview", financial_year_start: 2026)).not_to be_valid
    end

    it "rejects unknown statuses" do
      expect(user.investment_import_batches.new(source: "zerodha", status: "bogus", financial_year_start: 2026)).not_to be_valid
    end
  end

  describe ".preview scope" do
    it "filters batches in 'preview' status" do
      previewed = user.investment_import_batches.create!(source: "zerodha", status: "preview", financial_year_start: 2026)
      user.investment_import_batches.create!(source: "zerodha", status: "imported", financial_year_start: 2026)
      expect(user.investment_import_batches.preview).to contain_exactly(previewed)
    end
  end
end
