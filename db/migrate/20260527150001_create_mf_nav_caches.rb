# frozen_string_literal: true

# Phase 4 §6 — free public NAV API (mfapi.in / mfdata.in) integration.
#
# Stores the latest NAV (and optional history) for a mutual-fund scheme,
# keyed by either ISIN or AMFI scheme code. Refreshed lazily: each lookup
# checks staleness vs. FRESH_FOR (default 12h) and re-fetches from the
# upstream API on miss. The cache is per-app (not per-user) because NAVs
# are public data — no need to fan out per-user.
#
# Failure mode: if mfapi.in is unreachable (offline dev, CI, rate limit),
# PositionComputer falls back to using cost_basis as current_value and
# the UI shows a "live NAV unavailable" badge. This is the §4.6 graceful
# degradation contract.
class CreateMfNavCaches < ActiveRecord::Migration[8.0]
  def change
    create_table :mf_nav_caches do |t|
      t.string :scheme_code           # AMFI scheme code (mfapi.in's primary key)
      t.string :isin                  # ISIN if known
      t.string :scheme_name
      t.string :amc
      t.decimal :nav, precision: 14, scale: 4
      t.date :nav_date
      t.datetime :fetched_at
      t.string :source, default: 'mfapi.in', null: false
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :mf_nav_caches, :scheme_code, unique: true, where: 'scheme_code IS NOT NULL'
    add_index :mf_nav_caches, :isin, unique: true, where: 'isin IS NOT NULL'
    add_index :mf_nav_caches, :fetched_at
  end
end
