# frozen_string_literal: true

# Aggregates dashboard metrics for a date range (single request, SQL-efficient).
class DashboardSummaryService
  def initialize(user, range:, prev_range: nil, period_label:)
    @user = user
    @range = range
    @prev_range = prev_range
    @period_label = period_label
    @user_id = user.id
  end

  def call
    income = sum_credits
    expenses = sum_debits
    prev_income = @prev_range ? sum_credits(@prev_range) : 0.0
    prev_expenses = @prev_range ? sum_debits(@prev_range) : 0.0

    net_flow = income - expenses
    savings_rate = income.positive? ? ((net_flow / income) * 100).round(1) : nil

    {
      period_label: @period_label,
      income: income,
      expenses: expenses,
      net_flow: net_flow,
      savings_rate: savings_rate,
      income_change_pct: pct_change(income, prev_income),
      expenses_change_pct: pct_change(expenses, prev_expenses),
      transaction_count: tx_scope.count,
      uncategorized_count: uncategorized_count,
      recurring_count: recurring_count,
      top_merchants: top_merchants,
      top_categories: top_categories,
      budgets: budget_status,
      budget_vs_actual: budget_vs_actual,
      daily_spend: daily_spend_sparkline,
      net_worth: net_worth_snapshot,
      itr: itr_snapshot,
      credit_cards_count: @user.credit_cards.count,
    }
  end

  private

  def tx_scope(range = @range)
    Transaction.for_user(@user_id, date_range: range)
  end

  def sum_credits(range = @range)
    tx_scope(range).where(transaction_type: 'credit').sum(:amount).to_f
  end

  def sum_debits(range = @range)
    tx_scope(range).where(transaction_type: 'debit').sum(:amount).to_f
  end

  def pct_change(current, previous)
    return nil unless @prev_range
    return nil unless previous.positive?

    ((current - previous) / previous * 100).round(1)
  end

  def uncategorized_count
    unc = @user.categories.find_by('LOWER(name) = ?', 'uncategorized')
    return 0 unless unc

    tx_scope.where(transaction_type: 'debit', category_id: unc.id).count
  end

  def recurring_count
    tx_scope.where(transaction_type: 'debit', is_recurring: true).count
  end

  def top_merchants(limit: 5)
    tx_scope
      .where(transaction_type: 'debit')
      .where.not(merchant: [nil, ''])
      .group(:merchant)
      .sum(:amount)
      .sort_by { |_, v| -v }
      .first(limit)
      .map { |merchant, amount| { merchant: merchant, amount: amount.to_f } }
  end

  def top_categories(limit: 5)
    tx_scope
      .where(transaction_type: 'debit')
      .joins('LEFT JOIN categories ON categories.id = transactions.category_id')
      .group('categories.name', 'categories.color')
      .sum(:amount)
      .map { |k, v| { name: k[0] || 'Uncategorized', color: k[1] || '#94a3b8', amount: v.to_f } }
      .sort_by { |x| -x[:amount] }
      .first(limit)
  end

  def budget_rows(limit: nil)
    return [] unless single_calendar_month?

    month = @range.begin.month
    year = @range.begin.year
    month_budgets = @user.budgets.for_period(month, year).includes(:category).to_a
    general_budgets = @user.budgets.general.includes(:category).to_a

    rows = []
    (month_budgets + general_budgets).each do |budget|
      next if rows.any? { |r| r[:category_id] == budget.category_id }

      spent = spent_for_category(budget.category_id, month, year)
      amount = budget.amount.to_f
      next if amount <= 0 && spent <= 0

      rows << {
        category_id: budget.category_id,
        category_name: budget.category.name,
        category_color: budget.category.color,
        amount: amount,
        spent: spent,
        remaining: amount - spent,
        pct_used: amount.positive? ? [(spent / amount * 100).round, 999].min : nil,
      }
    end

    sorted = rows.sort_by { |r| -(r[:pct_used] || 0) }
    limit ? sorted.first(limit) : sorted
  end

  def budget_status
    budget_rows(limit: 5)
  end

  def budget_vs_actual
    budget_rows.map do |r|
      {
        name: r[:category_name],
        budget: r[:amount],
        actual: r[:spent],
        color: r[:category_color],
      }
    end
  end

  def daily_spend_sparkline(days: 30)
    end_date = [@range.end, Date.current].min
    start_date = end_date - (days - 1).days

    grouped = Transaction.for_user(@user_id, date_range: start_date..end_date)
                         .where(transaction_type: 'debit')
                         .group(:date)
                         .sum(:amount)

    total = grouped.values.sum.to_f
    avg = days.positive? ? (total / days).round(2) : 0

    points = (0...days).map do |i|
      d = start_date + i.days
      amt = grouped[d]&.to_f || 0.0
      {
        date: d.strftime('%d %b'),
        amount: amt,
        day: d.day,
      }
    end

    {
      points: points,
      total: total,
      daily_average: avg,
      days: days,
    }
  end

  def spent_for_category(category_id, month, year)
    Transaction
      .joins(statement: :bank_account)
      .where(bank_accounts: { user_id: @user_id })
      .where(transaction_type: 'debit', category_id: category_id)
      .where('EXTRACT(MONTH FROM transactions.date) = ?', month)
      .where('EXTRACT(YEAR FROM transactions.date) = ?', year)
      .sum(:amount)
      .to_f
  end

  def single_calendar_month?
    @range.begin.month == @range.end.month && @range.begin.year == @range.end.year
  end

  def net_worth_snapshot
    nw = NetWorthService.new(@user).call
    {
      net_worth_approx: nw[:net_worth_approx],
      total_invested: nw[:total_invested],
      total_bank: nw[:total_bank],
    }
  end

  def itr_snapshot
    fy = @user.user_preference.default_fy_start
    cache_key = ['dashboard/itr/v1', @user.id, fy, itr_cache_version(fy)]

    Rails.cache.fetch(cache_key, expires_in: 15.minutes) do
      readiness = ItrReadinessService.new(@user, financial_year_start: fy).call
      {
        financial_year_label: readiness[:financial_year_label],
        readiness_pct: readiness[:readiness_pct],
        suggested_form: readiness.dig(:suggested_itr_form, :form),
        cached_at: Time.current.iso8601,
      }
    end
  rescue StandardError => e
    Rails.logger.warn "Dashboard ITR snapshot: #{e.message}"
    nil
  end

  def itr_cache_version(fy)
    fy_range = FinancialYear.range_for(fy)
    doc_ts = @user.itr_tax_documents.where(financial_year_start: fy).maximum(:updated_at)&.to_i || 0
    txn_ts = Transaction.for_user(@user.id, date_range: fy_range).maximum(:updated_at)&.to_i || 0
    inv_ts = @user.investment_transactions.for_fy(fy).maximum(:updated_at)&.to_i || 0
    "#{doc_ts}-#{txn_ts}-#{inv_ts}"
  end
end
