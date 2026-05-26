# frozen_string_literal: true

# Estimates rewards left on the table when spend wasn't on the optimal card.
class RewardsGapAnalyzerService
  DEFAULT_EARN_RATE = 0.01 # assume 1% if no card rewards data

  def initialize(user, months_back: 3)
    @user = user
    @months_back = months_back
  end

  def call
    cards = @user.credit_cards.to_a
    spending = spending_by_category
    return empty_result('Add credit cards and upload statements.') if cards.empty?
    return empty_result('No spending data in this period.') if spending.empty?

    cards_with_rewards = cards.select { |c| (c.rewards_structure || {}).present? }
    return empty_result('Fetch rewards on your cards to see missed rewards.') if cards_with_rewards.empty?

    gaps = []
    total_missed = 0.0
    total_optimal = 0.0
    total_assumed = 0.0

    spending.each do |category, amount|
      next if skip_category?(category)
      next if amount.to_f < 100

      optimal = best_reward_among_cards(cards_with_rewards, category, amount)
      assumed = amount * DEFAULT_EARN_RATE
      missed = [optimal[:reward] - assumed, 0].max

      next if missed < 10 # ignore tiny gaps

      gaps << {
        category: category,
        amount_spent: amount.round(0),
        best_card: optimal[:card_name],
        best_rate: optimal[:rate_label],
        optimal_rewards: optimal[:reward].round(0),
        assumed_rewards: assumed.round(0),
        missed_rewards: missed.round(0),
      }
      total_missed += missed
      total_optimal += optimal[:reward]
      total_assumed += assumed
    end

    gaps.sort_by! { |g| -g[:missed_rewards] }

    {
      gaps: gaps.first(10),
      total_missed: total_missed.round(0),
      total_optimal: total_optimal.round(0),
      total_assumed: total_assumed.round(0),
      months_back: @months_back,
      message: nil,
    }
  end

  private

  def empty_result(message)
    { gaps: [], total_missed: 0, total_optimal: 0, total_assumed: 0, months_back: @months_back, message: message }
  end

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

  def skip_category?(category)
    %w[Transfer Income Uncategorized].include?(category.to_s)
  end

  def best_reward_among_cards(cards, category, amount)
    best = { reward: 0.0, card_name: nil, rate_label: nil }

    cards.each do |card|
      result = CardRewards::Calculator.best_rate_for_card(card, category, amount)
      next if result[:reward] <= best[:reward]

      entry = result[:entry] || {}
      rate_label = if entry['rate_type'] == 'percent'
                     "#{entry['rate']}%"
                   elsif entry['rate'].present?
                     "#{entry['rate']} pts/₹100"
                   else
                     'base'
                   end

      best = {
        reward: result[:reward],
        card_name: card.name,
        rate_label: rate_label,
      }
    end

    best
  end
end
