# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategoryRule, type: :model do
  let(:user) { make_user }
  let(:category) { user.categories.find_by(name: "Food & Dining") }

  describe "validations" do
    it "requires merchant_pattern" do
      rule = user.category_rules.new(category: category)
      expect(rule).not_to be_valid
      expect(rule.errors[:merchant_pattern]).to be_present
    end

    it "is valid with a pattern" do
      rule = user.category_rules.new(category: category, merchant_pattern: "swiggy")
      expect(rule).to be_valid
    end
  end

  describe "#matches?" do
    let(:rule) { user.category_rules.create!(category: category, merchant_pattern: "swiggy") }

    it "matches the pattern case-insensitively" do
      expect(rule.matches?("SWIGGY INDIA PVT LTD")).to be true
      expect(rule.matches?("Swiggy")).to be true
    end

    it "returns false for non-matching text" do
      expect(rule.matches?("AMAZON ORDER")).to be false
    end

    it "returns false for blank/nil input" do
      expect(rule.matches?(nil)).to be false
      expect(rule.matches?("")).to be false
    end
  end
end
