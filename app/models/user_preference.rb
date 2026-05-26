# frozen_string_literal: true

# Per-user settings stored in users.preferences (jsonb) with typed accessors.
class UserPreference
  DEFAULTS = {
    'default_fy_start' => nil,
    'auto_detect_investments' => true,
    'auto_categorize_statements' => true,
    'ai_enabled' => true,
    'ai_categorize' => true,
    'ai_create_categories' => true,
    'ai_context_months' => 6,
    'ai_agentic_enabled' => true,
    'ai_agentic_writes' => true,
    'ollama_url' => nil,
    'ollama_model' => nil,
    'salary_keywords' => [],
    'business_keywords' => [],
    'interest_keywords' => [],
    'preferred_tax_regime' => 'auto',
    'dashboard_view' => 'calendar_month',
    'reconciliation_tolerance_pct' => 10,
    'default_category_id' => nil,
    'dashboard_widgets' => nil,
    # Phase 6 §G13: how far back InvestmentDetectionService scans bank
    # narrations when looking for investment-like transactions. Default
    # 24 months matches the previous hardcoded 2.years.ago; clamped to
    # 1..120 in #investment_detect_lookback_months.
    'investment_detect_lookback_months' => 24,
  }.freeze

  PREFERRED_TAX_REGIMES = %w[auto old new].freeze
  DASHBOARD_VIEWS = %w[calendar_month financial_year].freeze

  DASHBOARD_WIDGET_IDS = %w[
    quick_actions
    alerts
    hero
    kpis
    daily_sparkline
    charts
    budget_vs_actual
    top_spend
    budgets_itr
    accounts
    transactions
  ].freeze

  DASHBOARD_WIDGET_DEFAULTS = DASHBOARD_WIDGET_IDS.freeze

  DASHBOARD_WIDGET_LABELS = {
    'quick_actions' => 'Quick actions',
    'alerts' => 'Alerts',
    'hero' => 'Net cash flow',
    'kpis' => 'Key metrics',
    'daily_sparkline' => 'Daily spending (30 days)',
    'charts' => 'Category & cash flow charts',
    'budget_vs_actual' => 'Budget vs actual',
    'top_spend' => 'Top merchants & categories',
    'budgets_itr' => 'Budgets, ITR & cards',
    'accounts' => 'Bank accounts',
    'transactions' => 'Recent transactions',
  }.freeze

  def initialize(user)
    @user = user
  end

  def [](key)
    get(key)
  end

  def get(key)
    key = key.to_s
    stored = @user.preferences[key]
    return DEFAULTS[key] if stored.nil?

    stored
  end

  def to_h
    DEFAULTS.keys.index_with { |k| serialized_value(k, get(k)) }
  end

  def update!(attrs)
    allowed = attrs.stringify_keys.slice(*DEFAULTS.keys)
    normalized = allowed.transform_keys(&:to_s).transform_values { |v| normalize_incoming(v) }
    @user.update!(preferences: @user.preferences.merge(normalized))
    @user.reload
    self
  end

  def default_fy_start
    v = get('default_fy_start')
    v.present? ? v.to_i : FinancialYear.current_start_year
  end

  def auto_detect_investments?
    get('auto_detect_investments') != false
  end

  def auto_categorize_statements?
    get('auto_categorize_statements') != false
  end

  def ai_enabled?
    get('ai_enabled') != false
  end

  def ai_categorize?
    ai_enabled? && get('ai_categorize') != false
  end

  def ai_create_categories?
    get('ai_create_categories') != false
  end

  def ai_context_months
    months = get('ai_context_months').to_i
    months = 6 if months < 1 || months > 24
    months
  end

  def ai_agentic_enabled?
    ai_enabled? && get('ai_agentic_enabled') != false
  end

  def ai_agentic_writes?
    ai_agentic_enabled? && get('ai_agentic_writes') != false
  end

  def ollama_url
    get('ollama_url').presence || ENV.fetch('OLLAMA_URL', 'http://localhost:11434')
  end

  def ollama_model
    get('ollama_model').presence || ENV.fetch('OLLAMA_MODEL', 'llama3.2')
  end

  def salary_keywords
    keyword_list('salary_keywords')
  end

  def business_keywords
    keyword_list('business_keywords')
  end

  def interest_keywords
    keyword_list('interest_keywords')
  end

  def reconciliation_tolerance_pct
    pct = get('reconciliation_tolerance_pct').to_f
    pct = 10.0 if pct <= 0 || pct > 50
    pct
  end

  # Phase 6 §G13. Clamped to 1..120 so a user can't accidentally
  # configure 0 (scan nothing) or 999 (scan their entire history,
  # melting the bank-detect query on a heavy user).
  def investment_detect_lookback_months
    months = get('investment_detect_lookback_months').to_i
    months = 24 if months < 1 || months > 120
    months
  end

  def preferred_tax_regime
    regime = get('preferred_tax_regime').to_s
    PREFERRED_TAX_REGIMES.include?(regime) ? regime : 'auto'
  end

  def dashboard_view
    view = get('dashboard_view').to_s
    DASHBOARD_VIEWS.include?(view) ? view : 'calendar_month'
  end

  def financial_year_dashboard?
    dashboard_view == 'financial_year'
  end

  def dashboard_widget_order
    stored = Array(get('dashboard_widgets')).map(&:to_s)
    valid = stored.select { |id| DASHBOARD_WIDGET_IDS.include?(id) }
    return DASHBOARD_WIDGET_DEFAULTS.dup if valid.blank?

    valid + (DASHBOARD_WIDGET_DEFAULTS - valid)
  end

  def dashboard_widget_catalog
    DASHBOARD_WIDGET_IDS.map do |id|
      { id: id, label: DASHBOARD_WIDGET_LABELS[id] || id.humanize }
    end
  end

  def description_pattern(base_pattern, extra_keywords)
    BankTransactionScopes.combined_description_pattern(base_pattern, extra_keywords)
  end

  private

  def keyword_list(key)
    Array(get(key)).map(&:to_s).map(&:strip).reject(&:blank?)
  end

  def normalize_incoming(value)
    case value
    when ActionController::Parameters then value.to_unsafe_h
    when Array then value.map(&:to_s).map(&:strip).reject(&:blank?)
    when 'true', 'false' then value == 'true'
    when String
      return [] if value.blank? && value != '0'
      value.include?(',') ? value.split(',').map(&:strip).reject(&:blank?) : value
    else value
    end
  end

  def serialized_value(key, value)
    case key
    when 'salary_keywords', 'business_keywords', 'interest_keywords'
      Array(value).join(', ')
    else value
    end
  end
end
