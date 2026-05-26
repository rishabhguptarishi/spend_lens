# frozen_string_literal: true

# Phase 4 §5.1 — Layer 2.
#
# Materialized rollup of every active (non-superseded) investment
# transaction for (user, holding, custodian). Refreshed by
# Investments::PositionComputer on writes; read on /net_worth and
# /investments without recomputing.
#
# Custodian is the entity HOLDING the units (broker / bank / depository).
# Distinct from `source` on activities (which is the ingestion channel).
# Same Infosys ISIN at Zerodha + at Groww = two positions.
class InvestmentPosition < ApplicationRecord
  CUSTODIAN_KINDS = %w[bank broker depository registrar pension pf insurer exchange unknown].freeze

  belongs_to :user
  belongs_to :investment_holding

  validates :custodian, :asset_class, presence: true

  scope :for_user, ->(user) { where(user: user) }
  scope :with_value, -> { where('current_value IS NOT NULL OR cost_basis > 0') }
  scope :nonzero,    -> { where('units > 0 OR cost_basis > 0') }

  # Current-value-or-fallback. Live NAV (`current_value`) when we have
  # it; cost basis otherwise. This is what the /net_worth page sums —
  # the §4 "graceful degradation" contract.
  def best_known_value
    return current_value.to_f if current_value.to_f > 0

    cost_basis.to_f
  end

  # Has live NAV been applied? Drives the "live nav unavailable" badge
  # on the UI when it's false for a market-priced instrument.
  def priced_with_nav?
    current_value.present? && current_value.to_f.positive? && current_nav.present?
  end

  def unrealized_gain
    return nil unless current_value.present? && cost_basis.present?

    current_value.to_f - cost_basis.to_f
  end

  def unrealized_return_pct
    return nil unless cost_basis.to_f.positive? && unrealized_gain

    (unrealized_gain / cost_basis.to_f) * 100.0
  end
end
