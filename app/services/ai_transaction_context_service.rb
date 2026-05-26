# frozen_string_literal: true

# Builds transaction context for the AI assistant — aggregates + search-matched rows.
class AiTransactionContextService
  MAX_RECENT = 300
  MAX_MATCHING = 40
  MONTHS_BACK = 6

  def initialize(user, question: nil)
    @user = user
    @question = question.to_s.strip
    @prefs = UserPreference.new(user)
    @months_back = @prefs.ai_context_months
  end

  def call
    base_scope = transaction_scope
    transactions = base_scope.order(date: :desc).limit(MAX_RECENT).to_a

    debits = transactions.select { |t| t.transaction_type == 'debit' }
    credits = transactions.select { |t| t.transaction_type == 'credit' }

    matching = search_matching_transactions(base_scope)

    {
      period: "last #{@months_back} months",
      total_transactions_in_period: base_scope.count,
      transactions_in_context: transactions.size,
      monthly_expenses: month_sum(base_scope, 'debit', 1.month.ago),
      monthly_income: month_sum(base_scope, 'credit', 1.month.ago),
      prev_month_expenses: month_sum(base_scope, 'debit', 2.months.ago, 1.month.ago),
      spending_change_pct: spending_change_pct(base_scope),
      top_categories: top_categories(debits),
      top_merchants: top_merchants(debits),
      credit_cards: credit_cards_summary,
      best_card_by_top_categories: best_card_hints(debits),
      recurring_transactions: recurring_sample(transactions),
      matching_transactions: serialize(matching),
      recent_transactions: serialize(transactions.first(50)),
      search_note: search_note(matching),
    }
  end

  private

  def transaction_scope
    Transaction
      .joins(statement: :bank_account)
      .includes(:category, statement: :bank_account)
      .where(bank_accounts: { user_id: @user.id })
      .where('transactions.date >= ?', @months_back.months.ago)
  end

  def search_matching_transactions(base_scope)
    terms = extract_search_terms(@question)
    return [] if terms.empty?

    scope = base_scope.left_joins(:category)
    clauses = []
    binds = []

    terms.each do |term|
      pattern = "%#{term.downcase}%"
      clauses << '(LOWER(transactions.description) LIKE ? OR LOWER(COALESCE(transactions.merchant, \'\')) LIKE ? OR LOWER(COALESCE(categories.name, \'\')) LIKE ?)'
      binds.concat([pattern, pattern, pattern])
    end

    scope.where(clauses.join(' OR '), *binds).distinct.order(date: :desc).limit(MAX_MATCHING).to_a
  end

  def extract_search_terms(question)
    return [] if question.blank?

    stop = %w[
      the a an and or but in on at to for of my me i how much what when where which who
      did do does is are was were have has had will can could would should about from
      last this that these those month year spending spent expense expenses transaction
      transactions show find list all any tell give
    ]

    terms = question.downcase
      .gsub(/[^\w\s@.-]/, ' ')
      .split(/\s+/)
      .reject { |w| w.length < 3 || stop.include?(w) }
      .uniq

    # Keep meaningful phrases (e.g. "swiggy", "vinayak", "salary")
    terms.first(5)
  end

  def serialize(transactions)
    transactions.map do |t|
      {
        date: t.date&.strftime('%Y-%m-%d'),
        description: t.description,
        amount: t.amount.to_f,
        category: t.category&.name,
        type: t.transaction_type,
        account: t.statement&.bank_account&.name,
        recurring: t.is_recurring,
      }
    end
  end

  def top_categories(debits)
    debits.group_by { |t| t.category&.name || 'Uncategorized' }
      .transform_values { |txs| { count: txs.size, total: txs.sum { |t| t.amount.to_f } } }
      .sort_by { |_, v| -v[:total] }
      .first(12)
      .map { |name, data| { category: name, count: data[:count], total: data[:total].round(0) } }
  end

  def top_merchants(debits)
    debits.group_by { |t| (t.description || 'Unknown').to_s[0..80] }
      .transform_values { |txs| txs.sum { |t| t.amount.to_f } }
      .sort_by { |_, v| -v }
      .first(12)
      .map { |name, amt| { merchant: name, amount: amt.round(0) } }
  end

  def recurring_sample(transactions)
    transactions.select(&:is_recurring).first(15).map do |t|
      { date: t.date&.strftime('%Y-%m-%d'), description: t.description, amount: t.amount.to_f, category: t.category&.name }
    end
  end

  def month_sum(scope, type, from, to = Date.current)
    scope.where(transaction_type: type).where(date: from..to).sum(:amount).to_f.round(0)
  end

  def spending_change_pct(scope)
    last = month_sum(scope, 'debit', 1.month.ago)
    prev = month_sum(scope, 'debit', 2.months.ago, 1.month.ago)
    prev.positive? ? ((last - prev) / prev * 100).round(1) : nil
  end

  def credit_cards_summary
    @user.credit_cards.map do |c|
      rewards = c.rewards_structure || {}
      cat_rewards = (rewards['category_rewards'] || []).first(5).map do |r|
        "#{r['category']}: #{r['rate']}#{r['rate_type'] == 'percent' ? '%' : ' pts/100'}"
      end
      { name: c.name, bank: c.bank_name, annual_fee: c.annual_fee.to_f, category_rewards: cat_rewards }
    end
  end

  def best_card_hints(debits)
    top_categories(debits).first(3).map do |tc|
      r = BestCardForPurchaseService.new(@user).call(category: tc[:category], amount: tc[:total] / 3.0)
      { category: r[:spend_category], best_card: r[:best]&.dig(:card_name), amount: r[:amount] }
    end
  end

  def search_note(matching)
    return nil if matching.empty? || extract_search_terms(@question).empty?

    "Found #{matching.size} transaction(s) matching your question keywords in matching_transactions."
  end
end
