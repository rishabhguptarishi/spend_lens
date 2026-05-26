# frozen_string_literal: true

require "rails_helper"

RSpec.describe AisReconciliationService, type: :service do
  let(:user) { make_user }

  subject(:service) { described_class.new(user, financial_year_start: 2026) }

  describe "#call with no documents" do
    it "returns rows with has_ais and has_form16 falsy" do
      result = service.call
      expect(result[:rows]).to be_an(Array).and(be_present)
      expect(result[:has_ais]).to be_falsey
      expect(result[:has_form16]).to be_falsey
    end

    it "includes the standard 6 reconciliation lines" do
      labels = service.call[:rows].map { |r| r[:label] }
      expect(labels).to include("Salary", "Interest", "Dividends", "STCG", "LTCG", "TDS")
    end
  end

  describe "#call with AIS data uploaded" do
    before do
      doc = user.itr_tax_documents.create!(
        document_type: "ais",
        financial_year_start: 2026,
        extraction_status: "extracted",
        extracted_data: { "salary" => 1_200_000, "interest" => 50_000, "dividends" => 5_000 }
      )
      doc.file.attach(io: StringIO.new("d"), filename: "ais.pdf", content_type: "application/pdf")
    end

    it "marks has_ais=true" do
      expect(service.call[:has_ais]).to be true
    end

    it "populates ais_amount in rows" do
      salary_row = service.call[:rows].find { |r| r[:label] == "Salary" }
      expect(salary_row[:ais_amount].to_f).to eq(1_200_000.0)
    end
  end
end
