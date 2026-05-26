# frozen_string_literal: true

class MonthlyDigestJob < ApplicationJob
  queue_as :default

  def perform
    User.includes(:user_notification_preference).find_each do |user|
      pref = user.user_notification_preference
      next if pref && !pref.monthly_digest

      DigestMailer.monthly_digest(user).deliver_later
    end
  end
end
