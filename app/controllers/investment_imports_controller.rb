# frozen_string_literal: true

class InvestmentImportsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_batch, only: [:show, :confirm, :destroy]

  def new
    render inertia: 'Investments/Import/New',
           props: {
             sources: InvestmentImportBatch::SOURCES,
             accounts: current_user.investment_accounts.order(:name),
             financial_year_start: FinancialYear.current_start_year,
             years: FinancialYear.available_years,
             large_import_bytes: InvestmentImportBatch::LARGE_FILE_BYTES,
           }
  end

  def create
    fy = (params[:financial_year_start] || FinancialYear.current_start_year).to_i
    source = params[:source].presence || 'generic_csv'
    file = params[:file]

    unless file.present?
      return redirect_to new_investment_import_path, alert: 'Please select a file.'
    end

    mapping = params[:column_mapping].present? ? params[:column_mapping].permit!.to_h : {}
    content = file.read
    async = large_import?(file, content)

    account_id = resolve_investment_account_id(params[:investment_account_id])

    batch = current_user.investment_import_batches.create!(
      source: source,
      status: async ? 'processing' : 'preview',
      financial_year_start: fy,
      preview_rows: [],
      column_mapping: mapping,
      investment_account_id: account_id,
      metadata: { 'filename' => file.original_filename, 'async' => async }
    )
    batch.file.attach(io: StringIO.new(content), filename: file.original_filename, content_type: file.content_type)

    if async
      ParseInvestmentImportJob.perform_later(batch.id)
      redirect_to investment_import_path(batch),
                  notice: 'Large file queued — parsing in the background. This page will refresh when ready.'
      return
    end

    rows = parse_content(content, file.original_filename, source, fy, mapping)
    if rows.empty?
      batch.destroy
      return redirect_to new_investment_import_path, alert: 'No transactions found. Try another format or generic CSV mapping.'
    end

    truncated = rows.size > InvestmentImportBatch::MAX_PREVIEW_ROWS
    preview = truncated ? rows.first(InvestmentImportBatch::MAX_PREVIEW_ROWS) : rows
    batch.update!(
      preview_rows: preview,
      metadata: batch.metadata.merge(
        'row_count' => rows.size,
        'preview_row_count' => preview.size,
        'truncated' => truncated
      )
    )
    redirect_to investment_import_path(batch)
  end

  def show
    if @batch.status == 'processing'
      return render inertia: 'Investments/Import/Processing',
                    props: { batch: batch_json(@batch) }
    end

    if @batch.status == 'failed'
      return render inertia: 'Investments/Import/Failed',
                    props: { batch: batch_json(@batch), error: @batch.metadata['error'] }
    end

    render inertia: 'Investments/Import/Preview',
           props: { batch: batch_json(@batch) }
  end

  def confirm
    alert_msg = nil
    count = 0

    @batch.with_lock do
      if @batch.status == 'processing'
        alert_msg = 'Import is still parsing. Please wait.'
        next
      end
      unless @batch.status == 'preview'
        alert_msg = 'This import was already completed or cancelled.'
        next
      end

      @batch.update!(preview_rows: params[:rows]) if params[:rows].present?
      count = InvestmentImports::Importer.new(current_user, @batch).call
    end

    if alert_msg
      return redirect_to investment_import_path(@batch), alert: alert_msg
    end

    redirect_to investments_activity_path(fy: @batch.financial_year_start),
                notice: "Imported #{count} transaction(s)."
  end

  def destroy
    fy = @batch.financial_year_start
    @batch.destroy
    redirect_to investments_path(fy: fy), notice: 'Import cancelled.'
  end

  private

  def set_batch
    @batch = current_user.investment_import_batches.find(params[:id])
  end

  def large_import?(file, content)
    return true if file.size >= InvestmentImportBatch::LARGE_FILE_BYTES

    estimate_row_count(content) >= InvestmentImportBatch::LARGE_ROW_ESTIMATE
  end

  def estimate_row_count(content)
    content.to_s.count("\n") + 1
  end

  def parse_content(content, filename, source, fy, mapping)
    InvestmentImports::ParserFacade.call(
      file_content: content,
      filename: filename,
      source: source,
      financial_year_start: fy,
      column_mapping: mapping
    )
  end

  def resolve_investment_account_id(id)
    return nil if id.blank?

    current_user.investment_accounts.find(id).id
  end

  def batch_json(batch)
    {
      id: batch.id,
      source: batch.source,
      status: batch.status,
      financial_year_start: batch.financial_year_start,
      financial_year_label: FinancialYear.label(batch.financial_year_start),
      preview_rows: batch.preview_rows,
      filename: batch.metadata['filename'],
      row_count: batch.metadata['row_count'],
      error: batch.metadata['error'],
      truncated: batch.metadata['truncated'],
    }
  end
end
