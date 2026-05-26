# frozen_string_literal: true

class ItrTaxDocumentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_document, only: [:confirm, :extract]

  def create
    fy = params[:financial_year_start].to_i
    doc_type = params[:document_type]
    entry = ItrDocumentRegistry.find(doc_type)
    unless entry
      return redirect_to itr_path(year: fy), alert: "Unknown document type: #{doc_type}"
    end

    # For singleton types (AIS, TIS, 26AS, etc.) reuse the existing row;
    # for multi-instance types (Form 16A, LIC, rent receipt) always
    # create a NEW row so the user can have many.
    doc =
      if entry.multiple_per_fy
        current_user.itr_tax_documents.new(
          financial_year_start: fy,
          document_type: doc_type
        )
      else
        current_user.itr_tax_documents.find_or_initialize_by(
          financial_year_start: fy,
          document_type: doc_type
        )
      end

    doc.assign_attributes(
      status: 'uploaded',
      extraction_status: 'pending',
      payer_name: params[:payer_name].presence,
      source_label: params[:source_label].presence,
      period_start: params[:period_start].presence,
      period_end: params[:period_end].presence
    )
    doc.file.attach(params[:file]) if params[:file].present?

    if doc.save
      ExtractTaxDocumentJob.perform_later(doc.id)
      redirect_to itr_path(year: fy), notice: "#{doc.display_label} uploaded — extracting…"
    else
      redirect_to itr_path(year: fy), alert: doc.errors.full_messages.join(', ')
    end
  end

  def extract
    ExtractTaxDocumentJob.perform_later(@document.id)
    redirect_to itr_document_confirm_path(@document), notice: 'Extraction started.'
  end

  def confirm
    if request.get?
      return render inertia: 'Itr/DocumentConfirm',
                    props: {
                      document: document_json(@document),
                    }
    end

    data = params[:confirmed_data].to_unsafe_h
    @document.update!(
      confirmed_data: data,
      extraction_status: 'confirmed'
    )

    if params[:force_resync] == '1' && @document.document_type.in?(%w[broker_pl mf_cg])
      TaxDocumentInvestmentSyncService.reset_sync!(@document)
    end

    synced = 0
    if @document.document_type.in?(%w[broker_pl mf_cg])
      synced = TaxDocumentInvestmentSyncService.new(current_user, @document).call
    end

    notice = 'Document data confirmed.'
    if synced.positive?
      notice += " #{synced} transaction(s) added to your portfolio."
    elsif @document.ledger_synced_at.present?
      notice += ' Portfolio already synced from this document.'
    end
    redirect_to itr_path(year: @document.financial_year_start), notice: notice
  end

  def destroy
    doc = current_user.itr_tax_documents.find(params[:id])
    fy = doc.financial_year_start
    doc.file.purge if doc.file.attached?
    doc.destroy
    redirect_to itr_path(year: fy), notice: 'Document removed.'
  end

  private

  def set_document
    @document = current_user.itr_tax_documents.find(params[:id])
  end

  def document_json(doc)
    {
      id: doc.id,
      document_type: doc.document_type,
      label: ItrTaxDocument.label_for(doc.document_type),
      display_label: doc.display_label,
      payer_name: doc.payer_name,
      source_label: doc.source_label,
      period_start: doc.period_start,
      period_end: doc.period_end,
      financial_year_start: doc.financial_year_start,
      extraction_status: doc.extraction_status,
      extracted_data: doc.extracted_data,
      confirmed_data: doc.confirmed_data,
    }
  end
end
