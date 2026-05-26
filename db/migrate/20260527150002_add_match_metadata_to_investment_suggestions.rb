# frozen_string_literal: true

# Phase 4 §5.7 — bucket suggestions by match-confidence in the UI.
#
# Three buckets per the doc's §5.7 row 2:
#   auto_resolved — confidence ≥ 0.9 + we'll auto-accept on user opt-in
#   likely_match  — confidence ∈ [0.5, 0.9): one-click confirm
#   unknown       — confidence < 0.5: explicit user choice (or dismiss)
#
# Confidence is computed by InvestmentDetectionService when it scans
# bank narrations:
#   - exact narration keyword (e.g. /\bppf\b/) + folio captured → 0.95
#   - exact keyword without folio                              → 0.70
#   - generic keyword match (e.g. "MF" prefix)                 → 0.50
#   - one-of-many ambiguous match                              → 0.30
class AddMatchMetadataToInvestmentSuggestions < ActiveRecord::Migration[8.0]
  def change
    add_column :investment_suggestions, :confidence, :decimal, precision: 4, scale: 3, default: 0.5, null: false
    add_column :investment_suggestions, :match_bucket, :string, default: 'unknown', null: false
    add_column :investment_suggestions, :metadata, :jsonb, default: {}

    add_index :investment_suggestions, %i[user_id match_bucket]
  end
end
