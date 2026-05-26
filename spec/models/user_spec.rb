# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "Devise validations" do
    it "is valid with an email + password" do
      expect(User.new(email: "u@example.com", password: "password123")).to be_valid
    end

    it "requires an email" do
      expect(User.new(password: "password123")).not_to be_valid
    end

    it "requires a password of at least 8 characters (Devise default)" do
      expect(User.new(email: "u@example.com", password: "1234567")).not_to be_valid
      expect(User.new(email: "u@example.com", password: "12345678")).to be_valid
    end

    it "requires unique emails" do
      User.create!(email: "dupe@example.com", password: "password123")
      expect(User.new(email: "dupe@example.com", password: "password123")).not_to be_valid
    end
  end

  describe "after_create callbacks" do
    let(:user) { make_user }

    it "seeds the 9 default categories" do
      expect(user.categories.count).to eq(User::DEFAULT_CATEGORIES.size)
      expect(user.categories.pluck(:name)).to include("Food & Dining", "Transport", "Shopping", "Income")
    end

    it "creates a UserNotificationPreference" do
      expect(user.user_notification_preference).to be_present
    end

    it "does NOT re-seed categories when called again" do
      expect { user.ensure_default_categories }.not_to change { user.categories.count }
    end
  end

  describe "#preferences" do
    it "returns an empty hash when nothing is stored" do
      expect(make_user.preferences).to eq({})
    end
  end

  describe "#user_preference" do
    it "returns a UserPreference wrapper" do
      expect(make_user.user_preference).to be_a(UserPreference)
    end
  end
end
