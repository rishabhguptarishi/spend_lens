# frozen_string_literal: true

class InvestmentImportBatch < ApplicationRecord
  # Sources currently used by parsers (zerodha, groww, hdfc_sec, mf_cas,
  # cdsl_cas, generic_csv). The remaining entries are pre-registered for
  # Phase 5 (depository / registrar) and Phase 1 (bank-statement portfolio
  # extraction) so future writers don't need a migration just to validate.
  SOURCES = %w[
    zerodha
    groww
    hdfc_sec
    mf_cas
    cdsl_cas
    nsdl_cas
    cams_cas
    kfintech_cas
    bank_statement
    generic_csv
  ].freeze
  STATUSES = %w[processing preview imported failed].freeze

  LARGE_FILE_BYTES = ENV.fetch('LARGE_IMPORT_BYTES', 512_000).to_i
  LARGE_ROW_ESTIMATE = ENV.fetch('LARGE_IMPORT_ROWS', 400).to_i
  MAX_PREVIEW_ROWS = ENV.fetch('IMPORT_MAX_PREVIEW_ROWS', 2_000).to_i

  belongs_to :user
  belongs_to :investment_account, optional: true
  has_one_attached :file

  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
  validates :financial_year_start, presence: true

  scope :preview, -> { where(status: 'preview') }
end
