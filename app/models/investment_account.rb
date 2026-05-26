# frozen_string_literal: true

class InvestmentAccount < ApplicationRecord
  ACCOUNT_KINDS = %w[broker mf_platform bank manual fd ppf nps epf crypto other].freeze

  belongs_to :user
  has_many :investment_holdings, dependent: :destroy
  has_many :investment_transactions, dependent: :nullify

  validates :name, presence: true
  validates :account_kind, inclusion: { in: ACCOUNT_KINDS }
end
