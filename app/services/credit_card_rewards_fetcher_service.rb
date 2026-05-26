# frozen_string_literal: true

# Fetches credit card rewards structure from AI (Ollama) based on card name and bank.
# Populates rewards_structure JSON for category-wise rates, caps, and special offers.
class CreditCardRewardsFetcherService
  def initialize(credit_card)
    @credit_card = credit_card
  end

  def call
    response = call_ollama(build_prompt)
    parse_response(response)
  rescue => e
    Rails.logger.warn "Credit card rewards fetch failed: #{e.message}"
    nil
  end

  private

  def build_prompt
    <<~PROMPT
      For the credit card "#{@credit_card.name}" by #{@credit_card.bank_name.presence || 'the bank'}, list its reward structure.
      Return ONLY valid JSON. No markdown, no explanation.

      Format:
      {
        "category_rewards": [
          {"category": "Dining", "rate": 5, "rate_type": "percent", "cap_amount": 500, "cap_period": "monthly", "description": "5% on dining"},
          {"category": "Groceries", "rate": 2, "rate_type": "percent", "description": "2% on groceries"}
        ],
        "base_reward": {"rate": 1, "rate_type": "points_per_100", "description": "1 point per ₹150 spent"},
        "special_offers": ["10x on Amazon", "5% on Swiggy", "2% fuel surcharge waiver"]
      }

      Rules:
      - category_rewards: Array of category-wise rewards. rate_type = "percent" or "points_per_100". cap_amount and cap_period optional.
      - base_reward: Default reward when no category match
      - special_offers: Array of strings for partner offers, bonus categories
      - Use Indian Rupee (₹) context. Categories: Dining, Groceries, Fuel, Travel, Shopping, Utilities, Entertainment, etc.
      - If you don't know the card, return empty arrays/objects. Be conservative.

      Card: #{@credit_card.name}, Bank: #{@credit_card.bank_name || 'Unknown'}
    PROMPT
  end

  def call_ollama(prompt)
    AiClient.chat(prompt, format: "json", temperature: 0)
  end

  def parse_response(response)
    return nil if response.blank?

    json_str = response.strip
    json_str = json_str[/```(?:json)?\s*([\s\S]*?)```/, 1] || json_str if json_str.include?('```')
    data = JSON.parse(json_str.strip)

    {
      'category_rewards' => Array(data['category_rewards']).map { |r| r.slice('category', 'rate', 'rate_type', 'cap_amount', 'cap_period', 'description') },
      'base_reward' => data['base_reward'].is_a?(Hash) ? data['base_reward'] : {},
      'special_offers' => Array(data['special_offers'])
    }
  rescue JSON::ParserError
    nil
  end
end
