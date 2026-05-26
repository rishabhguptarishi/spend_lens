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

  validates :date, :kind, :amount, :financial_year_start, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :source, inclusion: { in: SOURCES }

  before_validation :set_financial_year

  scope :for_fy, ->(year) { where(financial_year_start: year) }

  private

  def set_financial_year
    self.financial_year_start ||= FinancialYear.start_year_for(date) if date.present?
  end
end
