# frozen_string_literal: true

module CardRewards
  # Maps SpendLens expense categories to credit card reward category names.
  class CategoryMatcher
    SPEND_TO_REWARD = {
      'food & dining' => %w[dining food restaurant],
      'food' => %w[dining food restaurant],
      'transport' => %w[fuel transport travel commute],
      'shopping' => %w[shopping online retail amazon flipkart],
      'entertainment' => %w[entertainment movies ott streaming],
      'travel' => %w[travel flight hotel airline],
      'utilities' => %w[utilities bills electricity broadband],
      'healthcare' => %w[healthcare medical pharmacy],
      'transfer' => [],
      'income' => [],
      'uncategorized' => %w[shopping base all],
    }.freeze

    def self.reward_keywords_for(spend_category)
      key = spend_category.to_s.downcase.strip
      SPEND_TO_REWARD[key] || [key.split(/\s+/).first, 'base', 'all'].compact
    end

    def self.matches?(reward_category, spend_category)
      reward_cat = reward_category.to_s.downcase.strip
      return false if reward_cat.blank?

      keywords = reward_keywords_for(spend_category)
      keywords.any? { |kw| reward_cat.include?(kw) || kw.include?(reward_cat) } ||
        reward_cat == spend_category.to_s.downcase.strip
    end
  end
end
