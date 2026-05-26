# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserNotificationPreference, type: :model do
  let(:user) { make_user }

  it "belongs to a user" do
    expect(described_class.reflect_on_association(:user).macro).to eq(:belongs_to)
  end

  it "is autocreated for a new user" do
    expect(user.user_notification_preference).to be_present
  end

  it "exposes the notification keys constant" do
    expect(UserNotificationPreference::NOTIFICATION_KEYS).to all(be_a(String))
    expect(UserNotificationPreference::NOTIFICATION_KEYS).to include("monthly_digest")
  end
end
