# frozen_string_literal: true

class InvestmentHolding < ApplicationRecord
  # Master asset_class list. Phase 1.1 added reit, invit, p2p, fractional_re,
  # rsu, espp, esop per the architecture spec (docs/INVESTMENT_ARCHITECTURE.html
  # §3.2.7 + §5.2). Legacy values (gold, real_estate, other) retained for
  # backward-compatibility with rows created before the spec landed.
  ASSET_CLASSES = %w[
    mutual_fund stock bond fd rd ppf nps epf crypto gold real_estate
    reit invit p2p fractional_re rsu espp esop
    other
  ].freeze

  INFLOW_KINDS = %w[buy contribution sip transfer_in].freeze
  OUTFLOW_KINDS = %w[sell transfer_out maturity].freeze

  belongs_to :user
  belongs_to :investment_account
  has_many :investment_transactions, dependent: :nullify
  has_many :investment_positions, dependent: :destroy

  validates :name, :asset_class, presence: true
  validates :asset_class, inclusion: { in: ASSET_CLASSES }

  # Auto-compute the canonical identity_key whenever the holding is saved
  # if one isn't already set explicitly. Writers can opt out by setting
  # identity_key themselves (or pre-empting with nil for instruments we
  # can't dedup like manual real_estate). Skipping on update preserves
  # any backfilled key for legacy rows.
  before_validation :assign_identity_key, on: :create

  scope :with_identity_key, -> { where.not(identity_key: nil) }

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

  private

  def assign_identity_key
    return if identity_key.present?

    self.identity_key = Investments::IdentityKeyComputer.call(self)
  end
end
