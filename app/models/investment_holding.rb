# frozen_string_literal: true

class InvestmentHolding < ApplicationRecord
  ASSET_CLASSES = %w[
    mutual_fund stock bond fd rd ppf nps epf crypto gold real_estate other
  ].freeze

  INFLOW_KINDS = %w[buy contribution sip transfer_in].freeze
  OUTFLOW_KINDS = %w[sell transfer_out maturity].freeze

  belongs_to :user
  belongs_to :investment_account
  has_many :investment_transactions, dependent: :nullify

  validates :name, :asset_class, presence: true
  validates :asset_class, inclusion: { in: ASSET_CLASSES }

  # Re-derive units / invested_amount from the holding's own investment
  # transactions. Useful after fixing miscategorized rows, or any time we
  # suspect drift between the per-holding totals and the transaction history.
  def recompute_totals!
    invested = 0.0
    units    = 0.0

    investment_transactions.each do |t|
      amt = t.amount.to_f
      u   = t.units.to_f

      if INFLOW_KINDS.include?(t.kind)
        invested += amt
        units    += u
      elsif OUTFLOW_KINDS.include?(t.kind)
        invested -= amt
        units    -= u
      end
    end

    update!(invested_amount: [invested, 0].max, units: [units, 0].max)
  end

  def self.recompute_totals_for(user)
    where(user: user).find_each(&:recompute_totals!)
  end
end
