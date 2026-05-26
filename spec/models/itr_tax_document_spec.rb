# frozen_string_literal: true

require "rails_helper"

RSpec.describe ItrTaxDocument, type: :model do
  let(:user) { make_user }

  describe "validations" do
    it "requires document_type and financial_year_start" do
      doc = user.itr_tax_documents.new
      expect(doc).not_to be_valid
      expect(doc.errors.attribute_names).to include(:document_type, :financial_year_start)
    end

    it "rejects unknown document_type" do
      expect(user.itr_tax_documents.new(document_type: "bogus", financial_year_start: 2026)).not_to be_valid
    end

    it "is unique per (user, fy, document_type) for singleton types" do
      # ais is multiple_per_fy: false in the registry
      user.itr_tax_documents.create!(document_type: "ais", financial_year_start: 2026)
      dupe = user.itr_tax_documents.new(document_type: "ais", financial_year_start: 2026)
      expect(dupe).not_to be_valid
      expect(dupe.errors[:document_type].join).to include("already uploaded")
    end

    it "allows the same document_type for different FYs" do
      user.itr_tax_documents.create!(document_type: "ais", financial_year_start: 2025)
      expect(user.itr_tax_documents.new(document_type: "ais", financial_year_start: 2026)).to be_valid
    end

    it "allows multiple records of the same multi-instance type per FY" do
      # form16 (multiple employers), form16a (multiple banks), lic_premium, rent_receipt
      # are all multiple_per_fy: true in the registry.
      user.itr_tax_documents.create!(document_type: "form16", financial_year_start: 2026, payer_name: "Acme Pvt Ltd")
      second = user.itr_tax_documents.new(document_type: "form16", financial_year_start: 2026, payer_name: "Beta Corp")
      expect(second).to be_valid

      user.itr_tax_documents.create!(document_type: "form16a", financial_year_start: 2026, payer_name: "HDFC Bank")
      another = user.itr_tax_documents.new(document_type: "form16a", financial_year_start: 2026, payer_name: "ICICI Bank")
      expect(another).to be_valid
    end
  end

  describe "before_validation defaults" do
    it "defaults extraction_status to 'pending'" do
      doc = user.itr_tax_documents.create!(document_type: "ais", financial_year_start: 2026)
      expect(doc.extraction_status).to eq("pending")
    end
  end

  describe ".label_for" do
    it "returns human-readable labels for known types" do
      expect(described_class.label_for("form16")).to be_a(String).and(be_present)
      expect(described_class.label_for("ais")).to be_a(String).and(be_present)
      expect(described_class.label_for("form16a")).to include("Form 16A")
      expect(described_class.label_for("lic_premium")).to include("LIC")
    end
  end

  describe "registry integration" do
    it "exposes the registry entry's category" do
      doc = user.itr_tax_documents.create!(document_type: "form16", financial_year_start: 2026)
      expect(doc.category).to eq(:prefill)
    end

    it "denormalises deduction_section from the registry on save" do
      doc = user.itr_tax_documents.create!(document_type: "lic_premium", financial_year_start: 2026)
      expect(doc.reload.deduction_section).to eq("80C")
    end

    it "exposes applicable_forms" do
      cas = user.itr_tax_documents.create!(document_type: "cas_cdsl", financial_year_start: 2026)
      expect(cas.applicable_forms).to include("ITR-2")
      expect(cas.applicable_forms).not_to include("ITR-1") # ITR-1 cannot file Schedule CG
    end

    it "builds a display_label that disambiguates multi-instance docs" do
      hdfc = user.itr_tax_documents.create!(document_type: "form16a", financial_year_start: 2026, payer_name: "HDFC Bank")
      icici = user.itr_tax_documents.create!(document_type: "form16a", financial_year_start: 2026, payer_name: "ICICI Bank")
      expect(hdfc.display_label).to include("HDFC")
      expect(icici.display_label).to include("ICICI")
      expect(hdfc.display_label).not_to eq(icici.display_label)
    end
  end

  describe "#extracted?" do
    it "is true for 'extracted' and 'confirmed' statuses" do
      doc = user.itr_tax_documents.create!(document_type: "ais", financial_year_start: 2026)
      doc.update!(extraction_status: "extracted")
      expect(doc.extracted?).to be true
      doc.update!(extraction_status: "confirmed")
      expect(doc.extracted?).to be true
    end

    it "is false for pending / extracting / failed" do
      doc = user.itr_tax_documents.create!(document_type: "ais", financial_year_start: 2026)
      %w[pending extracting failed].each do |s|
        doc.update!(extraction_status: s)
        expect(doc.extracted?).to be(false), "expected false for status=#{s}"
      end
    end
  end

  describe "#effective_data" do
    it "prefers confirmed_data over extracted_data" do
      doc = user.itr_tax_documents.create!(
        document_type: "ais",
        financial_year_start: 2026,
        extracted_data: { "x" => 1 },
        confirmed_data: { "x" => 2 }
      )
      expect(doc.effective_data["x"]).to eq(2)
    end

    it "falls back to extracted_data when confirmed_data is blank" do
      doc = user.itr_tax_documents.create!(
        document_type: "ais",
        financial_year_start: 2026,
        extracted_data: { "x" => 1 }
      )
      expect(doc.effective_data["x"]).to eq(1)
    end
  end
end
