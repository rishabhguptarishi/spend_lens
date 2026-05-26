# frozen_string_literal: true

# Statement-driven portfolio analysis: gaps, high-spend categories, card ideas.
class StatementCardRecommendationsService
  HIGH_SPEND_THRESHOLD = 5000 # ₹ per 3 months

  def initialize(user, months_back: 3)
    @user = user
    @months_back = months_back
  end

  def call
    spending = spending_by_category
    cards = @user.credit_cards.to_a

    return { portfolio_gaps: [], high_spend_categories: [], message: 'Upload statements first.' } if spending.empty?

    portfolio_gaps = find_portfolio_gaps(spending, cards)
    high_spend = spending.sort_by { |_, v| -v }.first(8).map { |cat, amt| { category: cat, amount: amt.round(0) } }

    {
      portfolio_gaps: portfolio_gaps,
      high_spend_categories: high_spend,
      total_cards: cards.size,
      message: nil,
    }
  end

  private

  def spending_by_category
    range = @months_back.months.ago.beginning_of_month..Date.current.end_of_month
    Transaction
      .joins(statement: :bank_account)
      .joins('LEFT JOIN categories ON categories.id = transactions.category_id')
      .where(bank_accounts: { user_id: @user.id })
      .where(transaction_type: 'debit')
      .where(date: range)
      .group('COALESCE(categories.name, \'Uncategorized\')')
      .sum(:amount)
      .transform_values(&:to_f)
  end

  def find_portfolio_gaps(spending, cards)
    cards_with_rewards = cards.select { |c| (c.rewards_structure || {}).present? }
    gaps = []

    spending.each do |category, amount|
      next if %w[Transfer Income Uncategorized].include?(category)
      next if amount < HIGH_SPEND_THRESHOLD

      best_rate = 0.0
      best_card = nil

      cards_with_rewards.each do |card|
        result = CardRewards::Calculator.best_rate_for_card(card, category, amount)
        if result[:reward] > best_rate
          best_rate = result[:reward]
          best_card = card.name
        end
      end

      # Gap: high spend but no card gives >1% effective rewards
      effective_rate = amount.positive? ? (best_rate / amount * 100) : 0
      if cards_with_rewards.empty? || effective_rate < 2
        gaps << {
          category: category,
          amount_spent: amount.round(0),
          issue: cards_with_rewards.empty? ? 'no_cards_with_rewards' : 'low_rewards_coverage',
          suggestion: gap_suggestion(category, cards_with_rewards.empty?),
          best_existing_card: best_card,
          effective_reward_pct: effective_rate.round(1),
        }
      end
    end

    gaps.sort_by { |g| -g[:amount_spent] }.first(6)
  end

  def gap_suggestion(category, no_rewards)
    if no_rewards
      "Add your credit cards and fetch rewards to see if you're optimized."
    else
      "High spend on #{category} — consider a card with strong #{category.downcase} rewards, or use your best card for this category."
    end
  end
end
