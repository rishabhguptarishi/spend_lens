# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_notification_preferences

  def index
    prefs = current_user.user_preference
    notifications = current_user.user_notification_preference

    render inertia: 'Settings/Index',
           props: {
             preferences: prefs.to_h,
             notifications: notifications.as_json(only: UserNotificationPreference::NOTIFICATION_KEYS),
             investment_rules: current_user.user_investment_detection_rules.ordered.as_json(
               only: %w[id pattern asset_class kind account_name account_kind position]
             ),
             fy_years: FinancialYear.available_years,
             current_fy: FinancialYear.current_start_year,
             categories: current_user.categories.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } },
             asset_classes: UserInvestmentDetectionRule::ASSET_CLASSES,
             kinds: UserInvestmentDetectionRule::KINDS,
             account_kinds: UserInvestmentDetectionRule::ACCOUNT_KINDS,
             tax_regimes: UserPreference::PREFERRED_TAX_REGIMES,
             dashboard_views: UserPreference::DASHBOARD_VIEWS,
             system_detection_rules: InvestmentDetectionService::RULES.map do |r|
               { pattern: r[:pattern].inspect.delete_prefix('/').delete_suffix('/i'), asset_class: r[:asset_class], kind: r[:kind] }
             end,
           }
  end

  def update_preferences
    current_user.user_preference.update!(preference_params)
    redirect_to settings_path, notice: 'Settings saved.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_path, alert: e.message
  end

  def update_notifications
    current_user.user_notification_preference.update!(notification_params)
    redirect_to settings_path, notice: 'Notification preferences saved.'
  end

  private

  def ensure_notification_preferences
    current_user.ensure_notification_preferences
  end

  def preference_params
    p = params.require(:preferences).permit(
      :default_fy_start,
      :auto_detect_investments,
      :auto_categorize_statements,
      :ai_enabled,
      :ai_categorize,
      :ai_create_categories,
      :ai_context_months,
      :ai_agentic_enabled,
      :ai_agentic_writes,
      :ollama_url,
      :ollama_model,
      :preferred_tax_regime,
      :dashboard_view,
      :reconciliation_tolerance_pct,
      :default_category_id,
      :salary_keywords,
      :business_keywords,
      :interest_keywords
    )
    normalize_boolean_prefs(p)
    normalize_keyword_prefs(p)
    normalize_blank_prefs(p)
    p
  end

  def normalize_blank_prefs(p)
    %w[ollama_url ollama_model default_category_id].each do |key|
      p[key] = nil if p.key?(key) && p[key].blank?
    end
    p['default_fy_start'] = nil if p.key?('default_fy_start') && p['default_fy_start'].blank?
  end

  def notification_params
    p = params.require(:notifications).permit(*UserNotificationPreference::NOTIFICATION_KEYS)
    UserNotificationPreference::NOTIFICATION_KEYS.each do |key|
      p[key] = ActiveModel::Type::Boolean.new.cast(p[key]) if p.key?(key)
    end
    p
  end

  def normalize_boolean_prefs(p)
    %w[auto_detect_investments auto_categorize_statements ai_enabled ai_categorize ai_create_categories ai_agentic_enabled ai_agentic_writes].each do |key|
      p[key] = ActiveModel::Type::Boolean.new.cast(p[key]) if p.key?(key)
    end
  end

  def normalize_keyword_prefs(p)
    %w[salary_keywords business_keywords interest_keywords].each do |key|
      next unless p.key?(key)

      p[key] = p[key].to_s.split(',').map(&:strip).reject(&:blank?)
    end
  end
end
