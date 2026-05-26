# frozen_string_literal: true

require "rails_helper"

RSpec.describe StatementUploadsController, type: :request do
  let(:user) { make_user }

  before do
    sign_in(user)
    # Always pretend the parse job ran (no need to actually parse here)
    allow(ParseStatementJob).to receive(:perform_later)
  end

  # The extractor reads the file content & calls Ollama/Gemini in real life.
  # Stub it out and return a deterministic period for each spec.
  def stub_metadata(period_start:, period_end:, bank: "HDFC Bank", last_four: "1234")
    allow_any_instance_of(StatementMetadataExtractorService).to receive(:call).and_return({
      bank_name: bank,
      last_four: last_four,
      account_type: "credit_card",
      month: period_start.month,
      year: period_start.year,
      period_start: period_start,
      period_end: period_end,
    })
  end

  def upload_csv
    fixture_file_upload(
      Rails.root.join("spec/fixtures/files/sample.csv").to_s,
      "text/csv"
    )
  end

  before(:all) do
    path = Rails.root.join("spec/fixtures/files/sample.csv")
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "Date,Description,Amount\n2026-04-01,Coffee,-100\n") unless File.exist?(path)
  end

  describe "POST /upload" do
    context "when there is no overlap" do
      before { stub_metadata(period_start: Date.new(2026, 4, 1), period_end: Date.new(2026, 4, 30)) }

      it "creates the statement, enqueues parsing, and redirects to the statement show page" do
        expect {
          post statement_upload_path, params: { file: upload_csv }
        }.to change { Statement.count }.by(1)

        stmt = Statement.last
        expect(stmt.period_start).to eq(Date.new(2026, 4, 1))
        expect(stmt.period_end).to eq(Date.new(2026, 4, 30))
        expect(stmt.status).to eq("processing")
        expect(ParseStatementJob).to have_received(:perform_later).with(stmt.id)
        expect(response).to redirect_to(bank_account_statement_path(stmt.bank_account, stmt))
      end
    end

    context "when the new period overlaps an existing statement" do
      let!(:bank) { make_bank_account(user: user, bank_name: "HDFC Bank", last_four: "1234") }
      let!(:existing) do
        bank.statements.create!(
          month: 3, year: 2026,
          period_start: Date.new(2026, 3, 1),
          period_end: Date.new(2026, 3, 31),
          status: "parsed",
        )
      end

      before do
        # Full FY upload covering existing March statement
        stub_metadata(period_start: Date.new(2025, 4, 1), period_end: Date.new(2026, 3, 31))
      end

      it "puts the new statement in pending_overlap_review and routes to the overlap page" do
        expect {
          post statement_upload_path, params: { file: upload_csv }
        }.to change { Statement.count }.by(1)

        new_stmt = Statement.last
        expect(new_stmt.status).to eq("pending_overlap_review")
        expect(ParseStatementJob).not_to have_received(:perform_later)
        expect(response).to redirect_to(statement_overlap_review_path(new_stmt))
      end

      it "does not consider already-pending-review statements as overlapping (isolated case)" do
        existing.destroy! # Only the pending one remains
        bank.statements.create!(
          month: 5, year: 2025,
          period_start: Date.new(2025, 5, 1),
          period_end: Date.new(2025, 5, 31),
          status: "pending_overlap_review",
        )

        post statement_upload_path, params: { file: upload_csv }

        new_stmt = Statement.last
        # No resolved overlap left, so parsing should kick in directly.
        expect(new_stmt.status).to eq("processing")
        expect(ParseStatementJob).to have_received(:perform_later).with(new_stmt.id)
      end
    end

    context "when the file is missing or invalid" do
      it "rejects an absent file" do
        post statement_upload_path
        expect(response).to redirect_to(new_statement_upload_path)
        expect(flash[:alert]).to match(/select a file/i)
      end
    end
  end

  describe "GET /statements/:id/overlap_review" do
    let!(:bank) { make_bank_account(user: user, bank_name: "HDFC Bank", last_four: "1234") }
    let!(:existing) do
      bank.statements.create!(
        month: 3, year: 2026,
        period_start: Date.new(2026, 3, 1),
        period_end: Date.new(2026, 3, 31),
        status: "parsed",
      )
    end
    let!(:pending) do
      bank.statements.create!(
        month: 4, year: 2025,
        period_start: Date.new(2025, 4, 1),
        period_end: Date.new(2026, 3, 31),
        status: "pending_overlap_review",
      )
    end

    it "responds 200 and includes overlapping statement info in props" do
      get statement_overlap_review_path(pending), headers: { "X-Inertia" => "true" }
      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json.dig("props", "statement", "id")).to eq(pending.id)
      overlapping_ids = json.dig("props", "overlapping").map { |s| s["id"] }
      expect(overlapping_ids).to include(existing.id)
      expect(overlapping_ids).not_to include(pending.id)
    end

    it "redirects to the statement show page if the statement is no longer pending review" do
      pending.update!(status: "parsed")
      get statement_overlap_review_path(pending)
      expect(response).to redirect_to(bank_account_statement_path(pending.bank_account, pending))
    end
  end

  describe "PATCH /statements/:id/resolve_overlap" do
    let!(:bank) { make_bank_account(user: user, bank_name: "HDFC Bank", last_four: "1234") }
    let!(:existing) do
      bank.statements.create!(
        month: 3, year: 2026,
        period_start: Date.new(2026, 3, 1),
        period_end: Date.new(2026, 3, 31),
        status: "parsed",
      )
    end
    let!(:pending) do
      bank.statements.create!(
        month: 4, year: 2025,
        period_start: Date.new(2025, 4, 1),
        period_end: Date.new(2026, 3, 31),
        status: "pending_overlap_review",
      )
    end

    it "with resolution=replace destroys overlapping statements and enqueues parsing" do
      patch statement_resolve_overlap_path(pending), params: { resolution: "replace" }

      expect(Statement.exists?(existing.id)).to be false
      pending.reload
      expect(pending.status).to eq("processing")
      expect(ParseStatementJob).to have_received(:perform_later).with(pending.id)
      expect(response).to redirect_to(bank_account_statement_path(bank, pending))
    end

    it "with resolution=keep_both enqueues parsing without destroying anything" do
      patch statement_resolve_overlap_path(pending), params: { resolution: "keep_both" }

      expect(Statement.exists?(existing.id)).to be true
      pending.reload
      expect(pending.status).to eq("processing")
      expect(ParseStatementJob).to have_received(:perform_later).with(pending.id)
    end

    it "with resolution=cancel destroys the pending statement and leaves others alone" do
      patch statement_resolve_overlap_path(pending), params: { resolution: "cancel" }

      expect(Statement.exists?(pending.id)).to be false
      expect(Statement.exists?(existing.id)).to be true
      expect(ParseStatementJob).not_to have_received(:perform_later)
      expect(response).to redirect_to(new_statement_upload_path)
    end

    it "rejects an unknown resolution" do
      patch statement_resolve_overlap_path(pending), params: { resolution: "🤷" }
      expect(response).to redirect_to(statement_overlap_review_path(pending))
      pending.reload
      expect(pending.status).to eq("pending_overlap_review")
    end
  end
end
