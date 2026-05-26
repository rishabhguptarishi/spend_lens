# frozen_string_literal: true

module CardRewards
  # Estimates reward value in ₹ for a spend amount on a card's reward rule.
  class Calculator
    POINTS_TO_RUPEE = 0.25 # conservative: 4 reward points ≈ ₹1

    def self.reward_for(amount, reward_entry)
      return 0.0 if amount.to_f <= 0 || reward_entry.blank?

      rate = reward_entry['rate'].to_f
      return 0.0 if rate <= 0

      raw = case reward_entry['rate_type'].to_s
            when 'percent'
              amount.to_f * rate / 100.0
            when 'points_per_100'
              points = (amount.to_f / 100.0 * rate).floor
              points * POINTS_TO_RUPEE
            else
              amount.to_f * rate / 100.0
            end

      cap = reward_entry['cap_amount'].to_f
      cap.positive? ? [raw, cap].min : raw
    end

    def self.best_rate_for_card(card, spend_category, amount)
      structure = card.rewards_structure || {}
      category_rewards = structure['category_rewards'] || []
      base = structure['base_reward'] || {}

      matched = category_rewards.select do |r|
        CategoryMatcher.matches?(r['category'], spend_category)
      end

      best_entry = if matched.any?
                     matched.max_by { |r| reward_for(amount, r) }
                   elsif base.present? && base['rate'].to_f.positive?
                     base
                   end

      return { reward: 0.0, entry: nil, matched_category: nil } unless best_entry

      {
        reward: reward_for(amount, best_entry),
        entry: best_entry,
        matched_category: best_entry['category'],
      }
    end
  end
end
