# frozen_string_literal: true

# Suggests which credit card to use for each spending category to maximize rewards.
# Uses user's actual spending by category and card rewards structure.
class CreditCardRewardsSuggestorService
  def initialize(user)
    @user = user
  end

  def call(months_back: 3)
    cards = @user.credit_cards.includes(:user)
    return { suggestions: [], spending_by_category: {}, message: 'Add credit cards first.' } if cards.empty?

    spending = spending_by_category(months_back)
    return { suggestions: [], spending_by_category: spending, message: 'No spending data. Upload statements.' } if spending.empty?

    prompt = build_prompt(cards, spending)
    response = call_ollama(prompt)
    parse_suggestions(response, spending)
  rescue => e
    Rails.logger.warn "Rewards suggestion failed: #{e.message}"
    { suggestions: [], spending_by_category: {}, message: "AI unavailable: #{e.message}" }
  end

  private

  def spending_by_category(months_back)
    range = months_back.months.ago.beginning_of_month..Date.current.end_of_month
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

  def build_prompt(cards, spending)
    cards_data = cards.map do |c|
      rewards = c.rewards_structure || {}
      cat_rewards = (rewards['category_rewards'] || []).map { |r| "#{r['category']}: #{r['rate']}#{r['rate_type'] == 'percent' ? '%' : ' pts/100'}#{r['cap_amount'] ? " (cap ₹#{r['cap_amount']}/#{r['cap_period']})" : ''}" }.join('; ')
      "• #{c.name} (#{c.bank_name}): #{cat_rewards.presence || 'base rewards'}"
    end.join("\n")

    spending_str = spending.sort_by { |_, v| -v }.map { |cat, amt| "#{cat}: ₹#{amt.round(0)}" }.join(', ')

    <<~PROMPT
      Given the user's credit cards and their monthly spending by category, suggest which card to use for each category to MAXIMIZE rewards.
      Return ONLY valid JSON. No markdown, no explanation.

      User's cards and rewards:
      #{cards_data}

      User's spending (last 3 months total by category):
      #{spending_str}

      Return format:
      {
        "suggestions": [
          {"category": "Dining", "card": "HDFC Regalia", "reason": "5% rewards", "use_up_to": 10000, "estimated_rewards": 500},
          {"category": "Groceries", "card": "Axis Ace", "reason": "2% cashback", "use_up_to": null, "estimated_rewards": 200}
        ],
        "summary": "Use Regalia for dining and travel. Use Ace for groceries and utilities."
      }

      Rules:
      - use_up_to: Amount (₹) to use this card for this category before switching (consider caps). null if no cap.
      - estimated_rewards: Approximate rewards in ₹ for this category
      - Match categories from spending to card reward categories (Dining=Food, Groceries=Groceries, etc.)
      - Prefer higher reward rates. Consider caps - if cap is ₹500, use_up_to should reflect that
      - summary: 1-2 sentence actionable summary
    PROMPT
  end

  def call_ollama(prompt)
    AiClient.chat(prompt, format: "json", temperature: 0)
  end

  def parse_suggestions(response, spending)
    return { suggestions: [], spending_by_category: spending, message: 'Could not parse AI response.' } if response.blank?

    json_str = response.strip
    json_str = json_str[/```(?:json)?\s*([\s\S]*?)```/, 1] || json_str if json_str.include?('```')
    data = JSON.parse(json_str)

    suggestions = Array(data['suggestions']).map do |s|
      {
        'category' => s['category'],
        'card' => s['card'],
        'reason' => s['reason'],
        'use_up_to' => s['use_up_to'],
        'estimated_rewards' => s['estimated_rewards']
      }
    end

    {
      suggestions: suggestions,
      summary: data['summary'].to_s,
      spending_by_category: spending,
      message: nil
    }
  rescue JSON::ParserError
    { suggestions: [], spending_by_category: spending, message: 'Invalid AI response format.' }
  end
end
