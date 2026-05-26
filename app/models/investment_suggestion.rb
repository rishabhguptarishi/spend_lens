# frozen_string_literal: true

class InvestmentSuggestion < ApplicationRecord
  STATUSES = %w[pending accepted rejected].freeze

  # Phase 4 §5.7: bucket pending suggestions by match confidence so the
  # UI can render them in three tabs (Auto-resolved / Likely / Unknown).
  # Cutoffs match the doc's "auto vs likely vs unknown" recommendation:
  # ≥0.9 the rule was definitive (folio captured, exact narration);
  # ≥0.5 a strong-but-incomplete match; <0.5 ambiguous.
  MATCH_BUCKETS = %w[auto_resolved likely_match unknown].freeze
  HIGH_CONFIDENCE_THRESHOLD = 0.9
  MEDIUM_CONFIDENCE_THRESHOLD = 0.5

  belongs_to :user
  belongs_to :source_transaction, class_name: 'Transaction', foreign_key: 'transaction_id', inverse_of: :investment_suggestion

  validates :suggested_asset_class, :suggested_kind, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :transaction_id, uniqueness: true
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :match_bucket, inclusion: { in: MATCH_BUCKETS }

  before_validation :compute_match_bucket

  scope :pending, -> { where(status: 'pending') }
  scope :in_bucket, ->(b) { where(match_bucket: b) }
  scope :auto_resolved, -> { where(match_bucket: 'auto_resolved') }
  scope :likely_match,  -> { where(match_bucket: 'likely_match')  }
  scope :unknown_bucket, -> { where(match_bucket: 'unknown') }

  private

  # Derives the bucket from confidence. Lets writers just set confidence
  # (which is the natural unit; e.g. detection rules return a 0–1 score)
  # and have the bucket fall out automatically — UI never needs to do
  # threshold comparisons.
  def compute_match_bucket
    self.confidence ||= 0.5
    self.match_bucket =
      if confidence >= HIGH_CONFIDENCE_THRESHOLD
        'auto_resolved'
      elsif confidence >= MEDIUM_CONFIDENCE_THRESHOLD
        'likely_match'
      else
        'unknown'
      end
  end
end
