# frozen_string_literal: true

class UserInvestmentDetectionRule < ApplicationRecord
  belongs_to :user

  ASSET_CLASSES = %w[stock mutual_fund nps ppf fd crypto].freeze
  KINDS = %w[transfer_out buy contribution interest dividend sell transfer_in maturity sip].freeze
  ACCOUNT_KINDS = %w[broker mf_platform nps ppf fd crypto other].freeze

  validates :pattern, :asset_class, :kind, :account_name, presence: true
  validates :asset_class, inclusion: { in: ASSET_CLASSES }
  validates :kind, inclusion: { in: KINDS }
  validates :account_kind, inclusion: { in: ACCOUNT_KINDS }, allow_blank: true
  validates :pattern, uniqueness: { scope: :user_id, case_sensitive: false }
  validate :pattern_must_compile

  scope :ordered, -> { order(:position, :id) }

  def to_detection_rule
    {
      pattern: Regexp.new(pattern, Regexp::IGNORECASE),
      asset_class: asset_class,
      kind: kind,
      account_name: account_name,
      account_kind: account_kind.presence || 'other',
      custom: true,
    }
  end

  private

  def pattern_must_compile
    return if pattern.blank?

    Regexp.new(pattern, Regexp::IGNORECASE)
  rescue RegexpError => e
    errors.add(:pattern, "is invalid: #{e.message}")
  end
end
