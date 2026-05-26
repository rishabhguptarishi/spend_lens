# frozen_string_literal: true

class CategoryRule < ApplicationRecord
  belongs_to :user
  belongs_to :category

  validates :merchant_pattern, presence: true

  # Match if description/merchant contains pattern (case-insensitive)
  def matches?(text)
    return false if text.blank?

    text.to_s.downcase.include?(merchant_pattern.downcase)
  end
end
