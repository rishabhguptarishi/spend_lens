# frozen_string_literal: true

class InsightsController < ApplicationController
  before_action :authenticate_user!

  def index
    now = Date.current
    filter_type = params[:filter] || 'month' # month | range
    month = (params[:month] || now.month).to_i
    year = (params[:year] || now.year).to_i
    start_date = parse_date_param(params[:start_date])
    end_date = parse_date_param(params[:end_date])

    # Build date range
    if filter_type == 'range' && start_date.present? && end_date.present? && start_date <= end_date
      range = start_date..end_date
      days = (end_date - start_date).to_i + 1
      compare_range = (start_date - days.days)..(start_date - 1.day)
    else
      # Month/year filter
      month = [[month, 1].max, 12].min
      year = [[year, now.year - 10].max, now.year + 1].min
      range = Date.new(year, month, 1)..Date.new(year, month, -1)
      prev_month = Date.new(year, month, 1) - 1.month
      compare_range = prev_month.beginning_of_month..prev_month.end_of_month
    end

    tx_scope = Transaction
      .joins(statement: :bank_account)
      .where(bank_accounts: { user_id: current_user.id })
      .where(transaction_type: 'debit')

    period_expenses = tx_scope.where(date: range).sum(:amount).to_f
    compare_expenses = tx_scope.where(date: compare_range).sum(:amount).to_f
    change_pct = compare_expenses.positive? ? ((period_expenses - compare_expenses) / compare_expenses * 100).round(1) : 0

    by_category = tx_scope
      .where(date: range)
      .joins('LEFT JOIN categories ON categories.id = transactions.category_id')
      .group('categories.name', 'categories.color')
      .sum(:amount)
      .map { |k, v| { name: k[0] || 'Uncategorized', color: k[1] || '#94a3b8', amount: v } }
      .sort_by { |x| -x[:amount] }
      .first(10)

    top_merchants = tx_scope
      .where(date: range)
      .where.not(merchant: [nil, ''])
      .group(:merchant)
      .sum(:amount)
      .sort_by { |_, v| -v }
      .first(10)
      .map { |m, a| { merchant: m, amount: a } }

    months = (1..12).map { |m| [Date::MONTHNAMES[m], m] }.compact
    years = (now.year - 5..now.year).to_a.reverse

    rewards_gap = RewardsGapAnalyzerService.new(current_user).call

    render inertia: 'Insights/Index',
           props: {
             filter: filter_type,
             month: month,
             year: year,
             start_date: start_date&.to_s,
             end_date: end_date&.to_s,
             months: months,
             years: years,
             period_expenses: period_expenses,
             compare_expenses: compare_expenses,
             change_pct: change_pct,
             by_category: by_category,
             top_merchants: top_merchants,
             rewards_gap: rewards_gap,
           }
  end

  private

  def parse_date_param(val)
    return nil if val.blank?
    Date.parse(val.to_s)
  rescue ArgumentError
    nil
  end
end
