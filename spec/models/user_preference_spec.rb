# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserPreference, type: :model do
  let(:user) { make_user }
  let(:prefs) { described_class.new(user) }

  describe "defaults" do
    it "exposes a default ai_context_months of 6" do
      expect(prefs.ai_context_months).to eq(6)
    end

    it "exposes default boolean predicates" do
      expect(prefs.ai_enabled?).to be true
      expect(prefs.ai_categorize?).to be true
      expect(prefs.ai_create_categories?).to be true
    end

    it "treats preferred_tax_regime as 'auto' by default" do
      expect(prefs.preferred_tax_regime).to eq("auto")
    end
  end

  describe "#update!" do
    it "persists boolean values to user.preferences" do
      prefs.update!(ai_enabled: false)
      expect(user.reload.preferences["ai_enabled"]).to eq(false)
    end

    it "falls back to default (6) when ai_context_months is out of [1..24]" do
      prefs.update!(ai_context_months: 100)
      expect(user.reload.user_preference.ai_context_months).to eq(6)

      prefs.update!(ai_context_months: 0)
      expect(user.reload.user_preference.ai_context_months).to eq(6)
    end

    it "accepts in-range ai_context_months values verbatim" do
      prefs.update!(ai_context_months: 12)
      expect(user.reload.user_preference.ai_context_months).to eq(12)
    end

    it "rejects unknown tax regime values, falling back to 'auto'" do
      prefs.update!(preferred_tax_regime: "bogus")
      expect(user.reload.user_preference.preferred_tax_regime).to eq("auto")
    end
  end

  describe "#ollama_url and #ollama_model" do
    it "falls back to ENV values when not set" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("OLLAMA_URL", anything).and_return("http://example:11434")
      allow(ENV).to receive(:fetch).with("OLLAMA_MODEL", anything).and_return("custom-model")

      expect(prefs.ollama_url).to eq("http://example:11434")
      expect(prefs.ollama_model).to eq("custom-model")
    end
  end

  describe "#dashboard_widget_order" do
    it "returns a list of widget ids including all defaults" do
      order = prefs.dashboard_widget_order
      expect(order).to be_an(Array)
      expect(order).to include(*UserPreference::DASHBOARD_WIDGET_DEFAULTS)
    end
  end
end
