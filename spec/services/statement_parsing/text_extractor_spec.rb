# frozen_string_literal: true

require "rails_helper"

RSpec.describe StatementParsing::TextExtractor, type: :service do
  describe ".extract" do
    it "returns CSV content as UTF-8 string unchanged" do
      csv = "date,desc,amount\n2026-04-10,X,1\n"
      out = described_class.extract(csv.dup, extension: "csv")
      expect(out).to eq(csv)
      expect(out.encoding.name).to eq("UTF-8")
    end

    it "returns to_s for unknown extensions" do
      expect(described_class.extract("anything", extension: "xml")).to eq("anything")
    end

    it "delegates to extract_pdf for pdf extensions" do
      expect(described_class).to receive(:extract_pdf).with("BINARY").and_return("PDF TEXT")
      expect(described_class.extract("BINARY", extension: "pdf")).to eq("PDF TEXT")
    end
  end

  describe ".extract_pdf" do
    it "swallows errors from pdf-reader and returns a string (possibly empty)" do
      bogus = "not actually a PDF"
      out = described_class.extract_pdf(bogus)
      expect(out).to be_a(String)
    end
  end
end
