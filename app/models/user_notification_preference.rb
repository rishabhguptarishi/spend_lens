# frozen_string_literal: true

class UserNotificationPreference < ApplicationRecord
  belongs_to :user

  NOTIFICATION_KEYS = %w[monthly_digest investment_suggestions itr_season_reminders budget_alerts].freeze
end
