# frozen_string_literal: true

# Phase 4 §6 — mfapi.in NAV cache.
#
# One row per known scheme, keyed by AMFI scheme_code (primary key on
# the public API) or ISIN (which lets us correlate from CDSL CAS rows
# that only carry ISIN). Refreshed lazily via Investments::NavFetcher
# when older than FRESH_FOR; per-app, not per-user (public data).
class MfNavCache < ApplicationRecord
  # NAVs are published once per trading day at ~10 PM IST. A 12-hour
  # cache window comfortably catches the next day's publish while not
  # hammering mfapi.in on every page load.
  FRESH_FOR = 12.hours

  validates :nav, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :fresh, -> { where('fetched_at > ?', FRESH_FOR.ago) }
  scope :stale, -> { where('fetched_at IS NULL OR fetched_at <= ?', FRESH_FOR.ago) }

  def fresh?
    fetched_at.present? && fetched_at > FRESH_FOR.ago
  end

  def stale?
    !fresh?
  end
end
