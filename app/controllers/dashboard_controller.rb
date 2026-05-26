# frozen_string_literal: true

class DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_user_has_categories

  def index
    bank_accounts = current_user.bank_accounts.includes(:statements)
    range, period_label, prev_range, month, year, start_date, end_date = resolve_period

    user_id = current_user.id
    base_scope = Transaction.for_user(user_id, date_range: range)

    # Dashboard's recent-transactions widget only renders date/description/
    # category/amount — no statement or bank_account fields. Keeping these
    # joins/includes was over-fetching (Bullet was rightly flagging it).
    transactions = base_scope
      .includes(:category)
      .order(date: :desc)
      .limit(10)

    spending_by_category = base_scope
      .where(transaction_type: 'debit')
      .joins('LEFT JOIN categories ON categories.id = transactions.category_id')
      .group('categories.name', 'categories.color')
      .sum(:amount)
      .map { |k, v| { name: k[0] || 'Uncategorized', color: k[1] || '#94a3b8', value: v.to_f } }
      .sort_by { |x| -x[:value] }

    monthly_trend = build_monthly_trend(user_id, range.end)

    prefs = current_user.user_preference
    metrics = DashboardSummaryService.new(
      current_user,
      range: range,
      prev_range: prev_range,
      period_label: period_label
    ).call

    render inertia: 'Dashboard/Index',
           props: {
             widget_order: prefs.dashboard_widget_order,
             widget_catalog: prefs.dashboard_widget_catalog,
             bank_accounts: bank_accounts.as_json(include: :statements),
             recent_transactions: transactions.as_json(include: { category: {} }),
             spending_by_category: spending_by_category,
             monthly_trend: monthly_trend,
             metrics: metrics,
             month: month,
             year: year,
             start_date: start_date,
             end_date: end_date,
             period_label: period_label,
             pending_investment_suggestions: current_user.investment_suggestions.pending.count,
           }
  end

  def update_layout
    requested = Array(params[:widgets]).map(&:to_s)
    valid = requested & UserPreference::DASHBOARD_WIDGET_IDS
    valid = UserPreference::DASHBOARD_WIDGET_DEFAULTS if valid.blank?

    current_user.user_preference.update!(dashboard_widgets: valid)
    redirect_to dashboard_path(
      month: params[:month],
      year: params[:year],
      start_date: params[:start_date],
      end_date: params[:end_date]
    ), notice: 'Dashboard layout saved.'
  end

  private

  def resolve_period
    prefs = current_user.user_preference
    month = params[:month]&.to_i
    year = (params[:year] || Date.current.year).to_i
    start_date = params[:start_date]
    end_date = params[:end_date]
    prev_range = nil

    if start_date.blank? && end_date.blank? && prefs.financial_year_dashboard?
      fy = prefs.default_fy_start
      range = FinancialYear.range_for(fy)
      period_label = FinancialYear.label(fy)
    elsif start_date.present? && end_date.present?
      range = Date.parse(start_date)..Date.parse(end_date)
      period_label = "#{start_date} to #{end_date}"
      days = (range.end - range.begin).to_i + 1
      prev_range = (range.begin - days.days)..(range.begin - 1.day)
    else
      month = Date.current.month if month.blank? || month < 1 || month > 12
      year = Date.current.year if year < 2020 || year > 2030
      range = Date.new(year, month).beginning_of_month..Date.new(year, month).end_of_month
      month_end = range.end
      prev_range = (month_end - 1.month).beginning_of_month..(month_end - 1.month).end_of_month
      period_label = month_end.strftime('%B %Y')
    end

    [range, period_label, prev_range, month, year, start_date, end_date]
  end

  def build_monthly_trend(user_id, trend_end)
    trend_start = (trend_end - 5.months).beginning_of_month
    trend_range = trend_start..trend_end.end_of_month

    grouped = Transaction.for_user(user_id, date_range: trend_range)
                         .group(Arel.sql("DATE_TRUNC('month', transactions.date)"))
                         .pluck(
                           Arel.sql("DATE_TRUNC('month', transactions.date)"),
                           Arel.sql("SUM(CASE WHEN transaction_type = 'debit' THEN amount ELSE 0 END)"),
                           Arel.sql("SUM(CASE WHEN transaction_type = 'credit' THEN amount ELSE 0 END)")
                         )

    by_month = grouped.each_with_object({}) do |(month_time, expenses, income), h|
      key = month_time.to_date
      h[key] = { expenses: expenses.to_f, income: income.to_f }
    end

    5.downto(0).map do |i|
      month_start = (trend_end - i.months).beginning_of_month.to_date
      data = by_month[month_start] || { expenses: 0.0, income: 0.0 }
      {
        month: month_start.strftime('%b %Y'),
        expenses: data[:expenses],
        income: data[:income],
        net: data[:income] - data[:expenses],
      }
    end
  end

  def ensure_user_has_categories
    current_user.ensure_default_categories if current_user.categories.empty?
  end
end
