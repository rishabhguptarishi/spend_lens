# frozen_string_literal: true

# Handles the simplified upload flow:
#   POST /upload         → upload + auto-detect bank + period. If the new
#                          statement's period overlaps existing data, hold the
#                          new statement in `pending_overlap_review` and route
#                          the user to a confirmation screen.
#   PATCH /statements/:id/resolve_overlap → user picks Replace / Keep both /
#                                            Cancel and we proceed accordingly.
class StatementUploadsController < ApplicationController
  before_action :authenticate_user!

  def new
    render inertia: 'StatementUploads/New',
           props: { bank_accounts: current_user.bank_accounts }
  end

  def create
    file = params[:file]
    unless file.present?
      return redirect_to new_statement_upload_path, alert: 'Please select a file.'
    end

    ext = File.extname(file.original_filename.to_s).downcase
    unless %w[.csv .pdf].include?(ext)
      return redirect_to new_statement_upload_path, alert: 'Only CSV and PDF files are allowed.'
    end
    if file.size > 25.megabytes
      return redirect_to new_statement_upload_path, alert: 'File must be under 25 MB.'
    end

    # Extract metadata from file (bank, account, period)
    content = read_file_content(file)
    # Phase 6 §G16 — content-addressable dedup. SHA-256 of the file
    # bytes; lets us detect "same file uploaded again" deterministically.
    file.rewind
    raw_bytes = file.read
    file_sha = Digest::SHA256.hexdigest(raw_bytes)
    file.rewind
    metadata = StatementMetadataExtractorService.new(content, filename: file.original_filename).call

    bank_account = find_or_create_bank_account(metadata)

    # Phase 6 §G16: if the user double-clicks Upload, two requests fire
    # in parallel with identical files. The second one finds the first
    # one's statement here and redirects without creating a duplicate
    # row (which would trigger two parses and double-counted txns).
    if (existing = bank_account.statements.find_by(file_sha: file_sha))
      return redirect_to bank_account_statement_path(bank_account, existing),
                         notice: 'This file was already uploaded — showing the existing statement.'
    end

    statement = bank_account.statements.build(
      month: metadata[:month],
      year: metadata[:year],
      period_start: metadata[:period_start],
      period_end: metadata[:period_end],
      file_sha: file_sha,
      status: 'pending_overlap_review'
    )
    statement.file.attach(file)

    begin
      statement.save!
    rescue ActiveRecord::RecordNotUnique
      # Race: another request beat us to the unique index. Redirect to
      # the winner instead of erroring.
      winner = bank_account.statements.find_by(file_sha: file_sha)
      return redirect_to bank_account_statement_path(bank_account, winner),
                         notice: 'Upload already in progress — showing the existing statement.'
    rescue ActiveRecord::RecordInvalid
      return redirect_to new_statement_upload_path, alert: statement.errors.full_messages.join(', ')
    end

    # Ensure user has default categories for AI/keyword categorization
    current_user.ensure_default_categories if current_user.categories.empty?

    overlapping = find_overlapping_statements(bank_account, statement)

    if overlapping.any?
      redirect_to statement_overlap_review_path(statement),
                  notice: "We detected #{overlapping.size} existing statement(s) overlapping this period."
    else
      enqueue_parse(statement)
      redirect_to bank_account_statement_path(bank_account, statement),
                  notice: "Statement uploaded. Parsing in background. Account: #{bank_account.name}"
    end
  end

  # GET /statements/:id/overlap_review
  def overlap_review
    statement = current_user.bank_accounts
                            .joins(:statements)
                            .find_by("statements.id": params[:id])
                            &.statements
                            &.find_by(id: params[:id])
    return redirect_to new_statement_upload_path, alert: 'Statement not found.' unless statement

    unless statement.status == 'pending_overlap_review'
      return redirect_to bank_account_statement_path(statement.bank_account, statement)
    end

    overlapping = find_overlapping_statements(statement.bank_account, statement)
    render inertia: 'StatementUploads/OverlapReview',
           props: {
             statement: serialize_statement(statement),
             overlapping: overlapping.map { |s| serialize_statement(s) },
           }
  end

  # PATCH /statements/:id/resolve_overlap
  def resolve_overlap
    statement = current_user.bank_accounts
                            .joins(:statements)
                            .find_by("statements.id": params[:id])
                            &.statements
                            &.find_by(id: params[:id])
    return redirect_to new_statement_upload_path, alert: 'Statement not found.' unless statement

    case params[:resolution].to_s
    when 'replace'
      ActiveRecord::Base.transaction do
        find_overlapping_statements(statement.bank_account, statement).destroy_all
        enqueue_parse(statement)
      end
      redirect_to bank_account_statement_path(statement.bank_account, statement),
                  notice: 'Replaced overlapping statements. Parsing in background.'
    when 'keep_both'
      enqueue_parse(statement)
      redirect_to bank_account_statement_path(statement.bank_account, statement),
                  notice: 'Keeping existing statements. Parsing in background — duplicates will be skipped at the transaction level.'
    when 'cancel'
      bank_account = statement.bank_account
      statement.destroy
      redirect_to new_statement_upload_path, notice: 'Upload cancelled.'
    else
      redirect_to statement_overlap_review_path(statement), alert: 'Unknown resolution.'
    end
  end

  private

  # Statements on the same bank account whose period overlaps with the given
  # statement's period. Excludes the statement itself.
  def find_overlapping_statements(bank_account, statement)
    return Statement.none if statement.period_start.blank? || statement.period_end.blank?

    bank_account.statements
                .resolved
                .where.not(id: statement.id)
                .where("period_start IS NOT NULL AND period_end IS NOT NULL")
                .where("period_start <= ? AND period_end >= ?", statement.period_end, statement.period_start)
                .order(period_start: :desc)
  end

  def enqueue_parse(statement)
    statement.update!(status: 'processing')
    ParseStatementJob.perform_later(statement.id)
  end

  def serialize_statement(statement)
    {
      id: statement.id,
      month: statement.month,
      year: statement.year,
      period_start: statement.period_start,
      period_end: statement.period_end,
      period_label: statement.period_label,
      status: statement.status,
      transaction_count: statement.transactions.count,
      bank_account: {
        id: statement.bank_account.id,
        name: statement.bank_account.name,
        bank_name: statement.bank_account.bank_name,
      },
    }
  end

  def read_file_content(file)
    content = file.read
    ext = File.extname(file.original_filename).downcase.delete('.')
    if ext == 'pdf'
      require 'pdf-reader'
      reader = PDF::Reader.new(StringIO.new(content))
      reader.pages.map(&:text).join("\n")
    else
      content.force_encoding('UTF-8')
    end
  rescue => e
    Rails.logger.warn "File read failed: #{e.message}"
    ''
  end

  def find_or_create_bank_account(metadata)
    account_name = "#{metadata[:bank_name]} •••• #{metadata[:last_four]}"

    current_user.bank_accounts.find_or_initialize_by(
      bank_name: metadata[:bank_name],
      last_four: metadata[:last_four]
    ).tap do |account|
      account.name ||= account_name
      account.account_type ||= metadata[:account_type]
      account.save!
    end
  end
end
