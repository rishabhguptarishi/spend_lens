# frozen_string_literal: true

class ExtractTaxDocumentJob < ApplicationJob
  queue_as :default

  def perform(document_id)
    doc = ItrTaxDocument.find_by(id: document_id)
    return unless doc&.file&.attached?

    TaxDocumentExtractorService.new(doc).call
  rescue => e
    Rails.logger.error "ExtractTaxDocumentJob #{document_id}: #{e.message}"
    doc = ItrTaxDocument.find_by(id: document_id)
    doc&.update!(extraction_status: 'failed') unless doc&.extraction_status == 'confirmed'
    raise
  end
end
