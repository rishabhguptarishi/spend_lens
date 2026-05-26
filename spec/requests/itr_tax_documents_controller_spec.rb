# frozen_string_literal: true

require "rails_helper"

RSpec.describe ItrTaxDocumentsController, type: :request do
  let(:user) { make_user }

  before do
    sign_in(user)
    allow(ExtractTaxDocumentJob).to receive(:perform_later)
    path = Rails.root.join("spec/fixtures/files/dummy.pdf")
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "%PDF-1.4 dummy") unless File.exist?(path)
  end

  let(:pdf_upload) do
    fixture_file_upload(Rails.root.join("spec/fixtures/files/dummy.pdf").to_s, "application/pdf")
  end

  describe "POST /itr/documents" do
    it "creates a singleton document type (AIS) and refuses a second one in the same FY" do
      expect {
        post "/itr/documents", params: {
          financial_year_start: 2026,
          document_type: "ais",
          file: pdf_upload,
        }
      }.to change { ItrTaxDocument.count }.by(1)

      expect(response).to redirect_to(itr_path(year: 2026))
      expect(ExtractTaxDocumentJob).to have_received(:perform_later)

      # Second AIS upload should NOT create a new row (singleton — reuses existing)
      expect {
        post "/itr/documents", params: {
          financial_year_start: 2026,
          document_type: "ais",
          file: pdf_upload,
        }
      }.not_to change { ItrTaxDocument.count }
    end

    it "creates multiple Form 16As tagged by payer_name (multi-instance)" do
      expect {
        post "/itr/documents", params: {
          financial_year_start: 2026,
          document_type: "form16a",
          payer_name: "HDFC Bank",
          file: pdf_upload,
        }
      }.to change { ItrTaxDocument.count }.by(1)

      expect {
        post "/itr/documents", params: {
          financial_year_start: 2026,
          document_type: "form16a",
          payer_name: "ICICI Bank",
          file: pdf_upload,
        }
      }.to change { ItrTaxDocument.count }.by(1)

      docs = user.itr_tax_documents.for_fy(2026).of_type("form16a")
      expect(docs.pluck(:payer_name)).to contain_exactly("HDFC Bank", "ICICI Bank")
    end

    it "creates multiple LIC premium receipts under 80C" do
      3.times do |i|
        post "/itr/documents", params: {
          financial_year_start: 2026,
          document_type: "lic_premium",
          payer_name: "Policy ##{i + 1}",
          file: pdf_upload,
        }
      end
      lic_docs = user.itr_tax_documents.for_fy(2026).of_type("lic_premium")
      expect(lic_docs.count).to eq(3)
      expect(lic_docs.pluck(:deduction_section).uniq).to eq(["80C"])
    end

    it "rejects unknown document types with a flash alert" do
      expect {
        post "/itr/documents", params: {
          financial_year_start: 2026,
          document_type: "bogus_xyz",
          file: pdf_upload,
        }
      }.not_to change { ItrTaxDocument.count }
      expect(flash[:alert]).to include("Unknown document type")
    end
  end

  describe "DELETE /itr/documents/:id" do
    it "removes the specific instance even when other multi-instance siblings exist" do
      first = user.itr_tax_documents.create!(
        financial_year_start: 2026, document_type: "form16a", payer_name: "HDFC Bank"
      )
      second = user.itr_tax_documents.create!(
        financial_year_start: 2026, document_type: "form16a", payer_name: "ICICI Bank"
      )

      expect {
        delete "/itr/documents/#{first.id}"
      }.to change { ItrTaxDocument.count }.by(-1)

      expect(ItrTaxDocument.where(id: first.id)).to be_empty
      expect(ItrTaxDocument.where(id: second.id)).to be_present
    end
  end
end
