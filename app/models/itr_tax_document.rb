# frozen_string_literal: true

# A single uploaded artifact for ITR filing — Form 16, 16A, AIS, 26AS,
# broker P&L, deduction receipts, etc. The full taxonomy lives in
# ItrDocumentRegistry which is the source of truth for labels, validation,
# AI extraction schemas, and frontend grouping.
class ItrTaxDocument < ApplicationRecord
  EXTRACTION_STATUSES = %w[pending extracting extracted confirmed failed].freeze

  belongs_to :user
  has_one_attached :file

  validates :document_type, presence: true
  validate :document_type_known
  validates :financial_year_start, presence: true
  validates :extraction_status, inclusion: { in: EXTRACTION_STATUSES }, allow_nil: true
  validate :singleton_per_fy_when_required

  before_validation :default_extraction_status
  before_validation :denormalize_deduction_section

  scope :for_fy, ->(fy) { where(financial_year_start: fy.to_i) }
  scope :of_type, ->(type) { where(document_type: type.to_s) }
  scope :for_section, ->(sec) { where(deduction_section: sec.to_s) }
  scope :extracted, -> { where(extraction_status: %w[extracted confirmed]) }

  def self.document_types
    ItrDocumentRegistry.keys
  end

  def self.label_for(type)
    ItrDocumentRegistry.label_for(type)
  end

  def self.short_label_for(type)
    ItrDocumentRegistry.short_label_for(type)
  end

  def registry_entry
    ItrDocumentRegistry.find(document_type)
  end

  def multiple_per_fy?
    !!registry_entry&.multiple_per_fy
  end

  def category
    registry_entry&.category
  end

  def applicable_forms
    registry_entry&.applicable_forms || []
  end

  def extracted?
    extraction_status.in?(%w[extracted confirmed])
  end

  def effective_data
    confirmed_data.presence || extracted_data
  end

  # Display name that disambiguates multi-instance docs in the UI.
  # "Form 16A — HDFC Bank (Apr–Jun 2025)" reads better than just
  # "Form 16A" when a user has five of them.
  def display_label
    base = self.class.label_for(document_type)
    parts = [base]
    parts << "— #{payer_name}" if payer_name.present?
    parts << "(#{source_label})" if source_label.present? && payer_name.blank?
    parts.join(' ')
  end

  private

  def default_extraction_status
    self.extraction_status ||= 'pending'
  end

  # Mirror the registry's deduction_section onto the row so reports and
  # the savings advisor can aggregate without re-walking the registry.
  def denormalize_deduction_section
    return if deduction_section.present?

    self.deduction_section = registry_entry&.deduction_section
  end

  def document_type_known
    return if document_type.blank?
    return if ItrDocumentRegistry.find(document_type)

    errors.add(:document_type, "is not a recognised ITR document type")
  end

  # Only enforce singleton-ness for doc types where the IT dept actually
  # issues a single artifact per FY (Form 16, AIS, 26AS, TIS, PPF passbook
  # …). For multi-instance types (Form 16A from many banks, ELSS receipts,
  # rent receipts), the model silently allows duplicates and lets the user
  # disambiguate via payer_name / source_label.
  def singleton_per_fy_when_required
    return if document_type.blank? || financial_year_start.blank?
    return if multiple_per_fy?

    scope = self.class.where(
      user_id: user_id,
      financial_year_start: financial_year_start,
      document_type: document_type
    )
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?

    errors.add(:document_type,
               "already uploaded for FY #{financial_year_start} (one per year only)")
  end
end
