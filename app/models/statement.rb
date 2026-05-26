class Statement < ApplicationRecord
  belongs_to :bank_account
  has_many :transactions, dependent: :destroy
  has_one_attached :file

  STATUSES = %w[pending processing pending_overlap_review parsed failed].freeze

  validate :file_content_type_and_size

  scope :resolved, -> { where.not(status: 'pending_overlap_review') }

  # Returns true if this statement's period overlaps with the given range.
  # Treats missing period bounds as "no overlap" (caller should fall back to
  # month/year for legacy statements without a period set).
  def overlaps?(start_date, end_date)
    return false if period_start.blank? || period_end.blank? || start_date.blank? || end_date.blank?

    period_start <= end_date && period_end >= start_date
  end

  def period_label
    return "#{month}/#{year}" if period_start.blank? || period_end.blank?

    if period_start == period_end.beginning_of_month && period_end == period_end.end_of_month
      I18n.l(period_start, format: "%b %Y")
    else
      "#{I18n.l(period_start, format: '%d %b %Y')} – #{I18n.l(period_end, format: '%d %b %Y')}"
    end
  end

  private

  def file_content_type_and_size
    return unless file.attached?

    allowed = %w[application/pdf text/csv text/plain]
    unless file.blob.content_type.in?(allowed)
      errors.add(:file, 'must be PDF or CSV')
    end
    if file.blob.byte_size > 25.megabytes
      errors.add(:file, 'must be under 25 MB')
    end
  end
end
