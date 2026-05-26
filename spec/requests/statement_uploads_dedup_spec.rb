# frozen_string_literal: true

require "rails_helper"

# Phase 6 §G16: SHA-keyed dedup on upload. Same file uploaded twice
# (race or intentional) collapses to one Statement.
RSpec.describe StatementUploadsController, "upload dedup (Phase 6 §G16)", type: :request do
  let(:user) { make_user }
  let(:csv_content) { "Date,Description,Debit,Credit,Balance\n01/04/2025,STARBUCKS,100,,5000" }

  before do
    sign_in(user)
    # Stub the parsing job — we only care about the dedup behavior here.
    allow(ParseStatementJob).to receive(:perform_later)
    # Stub the metadata extractor's AI call — we don't need it for this
    # spec and don't want it to hit Gemini.
    allow_any_instance_of(StatementMetadataExtractorService).to receive(:call).and_return(
      bank_name: "HDFC", last_four: "1234", account_type: "savings",
      month: 4, year: 2026, period_start: Date.new(2025, 4, 1), period_end: Date.new(2025, 4, 30),
    )
  end

  def upload(content: csv_content, filename: "statement.csv")
    file = Rack::Test::UploadedFile.new(StringIO.new(content), "text/csv", original_filename: filename)
    post statement_upload_path, params: { file: file }
  end

  it "creates one statement on first upload and reuses it on the second" do
    upload
    expect(Statement.count).to eq(1)
    expect(response).to have_http_status(:redirect)

    # Second upload of byte-identical content — should reuse the row.
    upload
    expect(Statement.count).to eq(1)
    expect(response).to have_http_status(:redirect)
    expect(flash[:notice]).to include('already')
  end

  it "creates separate statements for files with different content (same name)" do
    upload(content: csv_content, filename: "statement.csv")
    upload(content: csv_content + "\n02/04/2025,COFFEE,50,,4950", filename: "statement.csv")

    expect(Statement.count).to eq(2)
    expect(Statement.distinct.pluck(:file_sha).compact.size).to eq(2)
  end
end
