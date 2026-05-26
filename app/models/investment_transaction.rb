# frozen_string_literal: true

class InvestmentTransaction < ApplicationRecord
  KINDS = %w[
    buy sell dividend interest contribution sip transfer_in transfer_out
    maturity fee other
  ].freeze
  SOURCES = %w[manual bank_detect broker_import mf_cas cdsl_cas bank_statement].freeze

  belongs_to :user
  belongs_to :investment_account, optional: true
  belongs_to :investment_holding, optional: true
  belongs_to :source_transaction, class_name: 'Transaction', foreign_key: 'transaction_id', optional: true, inverse_of: :investment_transaction

  # Supersession chain: when ActivityReconcilerService detects that two
  # activities describe the same real-world event from different sources,
  # the lower-priority one points at the higher-priority canonical row
  # via superseded_by_id. Both rows persist (for audit), but totals,
  # capital-gains, and ITR services should query the active scope (which
  # excludes superseded rows) to avoid double-counting.
  belongs_to :superseded_by, class_name: 'InvestmentTransaction', optional: true
  has_many :supersedes, class_name: 'InvestmentTransaction', foreign_key: :superseded_by_id, inverse_of: :superseded_by, dependent: :nullify

  validates :date, :kind, :amount, :financial_year_start, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :source, inclusion: { in: SOURCES }

  before_validation :set_financial_year
  before_validation :assign_source_priority

  scope :for_fy, ->(year) { where(financial_year_start: year) }
  scope :active, -> { where(superseded_by_id: nil) }
  scope :superseded, -> { where.not(superseded_by_id: nil) }

  # True when a higher-priority source attests to this same event, in
  # which case the row should be hidden from rollups (still queryable
  # for the audit/activity log).
  def superseded?
    superseded_by_id.present?
  end

  # Add a source name to the confirmed_by audit list, idempotently.
  def confirm_with!(source_name)
    name = source_name.to_s
    return if name.blank?
    return if (confirmed_by || []).include?(name)

    self.confirmed_by = (confirmed_by || []) + [name]
    save!
  end

  private

  def set_financial_year
    self.financial_year_start ||= FinancialYear.start_year_for(date) if date.present?
  end

  def assign_source_priority
    return if source_priority.present?
    return if source.blank?

    self.source_priority = Investments::SourcePriority.for(source)
  end
end
