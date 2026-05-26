# frozen_string_literal: true

# Analyzes whether annual fees are worth it based on spend and card rewards.
class CreditCardFeeAnalysisService
  def initialize(user, months_back: 12)
    @user = user
    @months_back = months_back
  end

  def call
    cards = @user.credit_cards.to_a
    return [] if cards.empty?

    spending = total_spending_by_category
    months = @months_back

    cards.map do |card|
      analyze_card(card, spending, months)
    end.sort_by { |a| -a[:estimated_annual_rewards] }
  end

  private

  def total_spending_by_category
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

  def analyze_card(card, spending, months)
    annual_fee = card.annual_fee.to_f
    fee_waiver = card.fee_waiver_spend.to_f
    structure = card.rewards_structure || {}

    monthly_rewards = 0.0
    spending.each do |category, total|
      next if %w[Transfer Income].include?(category)

      monthly_amount = total / [months, 1].max
      result = CardRewards::Calculator.best_rate_for_card(card, category, monthly_amount)
      monthly_rewards += result[:reward]
    end

    estimated_annual_rewards = (monthly_rewards * 12).round(0)
    net_value = estimated_annual_rewards - annual_fee
    waiver_progress = fee_waiver.positive? ? spending.values.sum / fee_waiver * 100 : nil

    {
      card_id: card.id,
      card_name: card.name,
      bank_name: card.bank_name,
      annual_fee: annual_fee.round(0),
      fee_waiver_spend: fee_waiver.round(0),
      estimated_annual_rewards: estimated_annual_rewards,
      net_value: net_value.round(0),
      worth_it: annual_fee.zero? || net_value >= 0,
      waiver_progress_pct: waiver_progress&.round(0),
      waiver_met: fee_waiver.positive? && spending.values.sum >= fee_waiver,
      has_rewards_data: structure.present?,
      recommendation: recommendation_text(annual_fee, estimated_annual_rewards, net_value, fee_waiver, spending.values.sum),
    }
  end

  def recommendation_text(fee, rewards, net, waiver_target, total_spend)
    return 'No annual fee — keep using this card.' if fee <= 0
    return 'Fetch card rewards to estimate if the fee is worth it.' if rewards.zero?

    if net >= fee * 0.5
      "Worth it — estimated rewards (₹#{rewards}) exceed the ₹#{fee.to_i} fee."
    elsif waiver_target.positive? && total_spend >= waiver_target
      "Fee likely waived — you've met the ₹#{waiver_target.to_i} spend threshold."
    elsif waiver_target.positive? && total_spend < waiver_target
      remaining = (waiver_target - total_spend).round(0)
      "Spend ₹#{remaining} more to waive the ₹#{fee.to_i} annual fee."
    else
      "Consider downgrading — rewards may not cover the ₹#{fee.to_i} fee (net ₹#{net})."
    end
  end
end
