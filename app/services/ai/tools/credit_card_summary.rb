# frozen_string_literal: true

module Ai
  module Tools
    class CreditCardSummary < Base
      def self.description
        'List the user\'s credit cards with their reward structures and annual fees.'
      end

      def self.parameters_schema
        { type: 'object', properties: {} }
      end

      def call(_args)
        cards = @user.credit_cards.map do |c|
          rewards = c.rewards_structure || {}
          category_rewards = Array(rewards['category_rewards']).first(8).map do |r|
            {
              category: r['category'],
              rate: r['rate'],
              rate_type: r['rate_type'],
              cap: r['cap'],
            }
          end

          {
            id: c.id,
            name: c.name,
            bank: c.bank_name,
            annual_fee: c.annual_fee.to_f,
            base_reward_rate: rewards['base_rate'],
            base_reward_type: rewards['base_rate_type'],
            category_rewards: category_rewards,
            milestones: Array(rewards['milestones']).first(4),
          }
        end
        { count: cards.size, cards: cards }
      end
    end
  end
end
