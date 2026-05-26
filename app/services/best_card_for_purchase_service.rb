# frozen_string_literal: true

# Recommends which credit card to use for a purchase (category, merchant, or amount).
class BestCardForPurchaseService
  def initialize(user)
    @user = user
  end

  def call(category: nil, merchant: nil, amount: nil)
    cards = @user.credit_cards.to_a
    return { recommendations: [], message: 'Add credit cards first.' } if cards.empty?

    spend_category = infer_category(category, merchant)
    amount = amount.to_f
    amount = 1000.0 if amount <= 0 # default for comparison

    cards_with_rewards = cards.select { |c| (c.rewards_structure || {}).present? }
    if cards_with_rewards.empty?
      return {
        recommendations: cards.map { |c| { card_id: c.id, card_name: c.name, reward: 0, rate_label: 'Fetch rewards first' } },
        spend_category: spend_category,
        amount: amount,
        message: 'Fetch rewards on your cards for accurate recommendations.',
      }
    end

    ranked = cards_with_rewards.map do |card|
      result = CardRewards::Calculator.best_rate_for_card(card, spend_category, amount)
      entry = result[:entry] || {}
      rate_label = format_rate(entry)

      {
        card_id: card.id,
        card_name: card.name,
        bank_name: card.bank_name,
        reward: result[:reward].round(0),
        rate_label: rate_label,
        matched_category: result[:matched_category],
      }
    end.sort_by { |r| -r[:reward] }

    {
      recommendations: ranked,
      best: ranked.first,
      spend_category: spend_category,
      amount: amount,
      message: nil,
    }
  end

  private

  def infer_category(category, merchant)
    return category.to_s.strip if category.present?

    text = merchant.to_s.downcase
    return 'Food & Dining' if text.match?(/swiggy|zomato|restaurant|food|dining/)
    return 'Shopping' if text.match?(/amazon|flipkart|myntra|shop/)
    return 'Transport' if text.match?(/uber|ola|fuel|petrol|irctc/)
    return 'Entertainment' if text.match?(/netflix|spotify|bookmyshow/)
    return 'Travel' if text.match?(/makemytrip|goibibo|hotel|flight/)
    return 'Utilities' if text.match?(/electricity|recharge|broadband|jio|airtel/)

    'Shopping'
  end

  def format_rate(entry)
    return 'No rewards data' if entry.blank? || entry['rate'].blank?

    if entry['rate_type'] == 'percent'
      "#{entry['rate']}%"
    else
      "#{entry['rate']} pts/₹100"
    end
  end
end
