# frozen_string_literal: true

class CreditCard < ApplicationRecord
  belongs_to :user

  CARD_TYPES = %w[rewards cashback travel fuel lifestyle premium].freeze

  validates :name, presence: true

  def category_rewards
    rewards_structure&.dig('category_rewards') || []
  end

  def special_offers
    rewards_structure&.dig('special_offers') || []
  end

  def base_reward
    rewards_structure&.dig('base_reward') || {}
  end
end
