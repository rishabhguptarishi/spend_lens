# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserInvestmentDetectionRule, type: :model do
  let(:user) { make_user }

  def build_rule(**overrides)
    user.user_investment_detection_rules.new({
      pattern: "ZERODHA",
      asset_class: "stock",
      kind: "buy",
      account_name: "Zerodha",
      account_kind: "broker",
    }.merge(overrides))
  end

  describe "validations" do
    it "is valid with the minimum required attributes" do
      expect(build_rule).to be_valid
    end

    it "requires pattern, asset_class, kind, account_name" do
      rule = user.user_investment_detection_rules.new
      expect(rule).not_to be_valid
    end

    it "rejects unknown asset_class" do
      expect(build_rule(asset_class: "bogus")).not_to be_valid
    end

    it "rejects unknown kind" do
      expect(build_rule(kind: "bogus")).not_to be_valid
    end

    it "rejects invalid regex patterns" do
      rule = build_rule(pattern: "[invalid")
      expect(rule).not_to be_valid
      expect(rule.errors[:pattern].join).to match(/invalid/i)
    end

    it "enforces uniqueness of pattern per user (case-insensitive)" do
      build_rule(pattern: "ZERODHA").save!
      expect(build_rule(pattern: "zerodha")).not_to be_valid
    end
  end

  describe "#to_detection_rule" do
    it "returns a hash with a compiled Regexp" do
      rule = build_rule.tap(&:save!)
      result = rule.to_detection_rule
      expect(result).to include(:pattern, :asset_class, :kind, :account_name, :account_kind)
      expect(result[:pattern]).to be_a(Regexp)
      expect(result[:custom]).to be true
    end
  end

  describe ".ordered scope" do
    it "orders by position then id" do
      build_rule(pattern: "B", position: 2).save!
      build_rule(pattern: "A", position: 1).save!
      expect(user.user_investment_detection_rules.ordered.first.pattern).to eq("A")
    end
  end
end
