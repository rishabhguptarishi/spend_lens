# frozen_string_literal: true

# Phase 4 §5.1 — Layer 2 of the three-layer data model.
#
# A Position is the materialized rollup of every active (non-superseded)
# InvestmentTransaction for a given (user, instrument, custodian) tuple.
# Instrument here is collapsed onto InvestmentHolding (which already
# carries the canonical identity_key from Phase 1). The custodian is
# the entity actually HOLDING the units (broker / bank / depository) —
# distinct from the SOURCE that told us about it (CSV / passbook / CAS).
#
# Why a table, not a view: positions are read by /net_worth on every
# page load; recomputing them across 1000+ activities per page render
# is wasteful. We materialize on writes, read on reads. PositionComputer
# does the materialization.
#
# Why unique(user_id, investment_holding_id, custodian): one position
# per (you, the security, the place it lives). The same Infosys ISIN
# at Zerodha AND at Groww = two positions. The same PPF account at
# one bank = one position.
class CreateInvestmentPositions < ActiveRecord::Migration[8.0]
  def change
    create_table :investment_positions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :investment_holding, null: false, foreign_key: true
      t.string :custodian, default: 'unknown', null: false
      t.string :asset_class, null: false
      t.decimal :units, precision: 18, scale: 6, default: 0.0
      t.decimal :cost_basis, precision: 14, scale: 2, default: 0.0
      t.decimal :current_value, precision: 14, scale: 2
      t.decimal :current_nav, precision: 14, scale: 4
      t.date :as_of_date
      t.datetime :computed_at
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :investment_positions, %i[user_id investment_holding_id custodian],
      unique: true,
      name: 'index_investment_positions_on_user_holding_custodian'
    add_index :investment_positions, %i[user_id asset_class]
    add_index :investment_positions, :computed_at
  end
end
