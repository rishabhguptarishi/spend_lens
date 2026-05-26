# frozen_string_literal: true

class ParseInvestmentImportJob < ApplicationJob
  queue_as :default

  def perform(batch_id)
    batch = InvestmentImportBatch.find_by(id: batch_id)
    return unless batch&.file&.attached?

    batch.update!(status: 'processing', metadata: batch.metadata.merge('started_at' => Time.current.iso8601))

    content = batch.file.download
    rows = InvestmentImports::ParserFacade.call(
      file_content: content,
      filename: batch.metadata['filename'] || batch.file.filename.to_s,
      source: batch.source,
      financial_year_start: batch.financial_year_start,
      column_mapping: batch.column_mapping
    )

    if rows.empty?
      batch.update!(
        status: 'failed',
        metadata: batch.metadata.merge('error' => 'No transactions found in file.')
      )
      return
    end

    truncated = rows.size > InvestmentImportBatch::MAX_PREVIEW_ROWS
    preview = truncated ? rows.first(InvestmentImportBatch::MAX_PREVIEW_ROWS) : rows

    batch.update!(
      status: 'preview',
      preview_rows: preview,
      metadata: batch.metadata.merge(
        'row_count' => rows.size,
        'preview_row_count' => preview.size,
        'truncated' => truncated,
        'parsed_at' => Time.current.iso8601
      )
    )
  rescue => e
    Rails.logger.error "ParseInvestmentImportJob #{batch_id}: #{e.message}"
    batch&.update!(
      status: 'failed',
      metadata: (batch.metadata || {}).merge('error' => e.message)
    )
  end
end
