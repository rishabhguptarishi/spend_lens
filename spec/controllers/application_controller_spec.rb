# frozen_string_literal: true

require "rails_helper"

# Guards the global Inertia share that exposes ai_provider + ai_provider_label
# to every page. Previously the frontend hardcoded "Ollama" everywhere because
# this share didn't exist.
RSpec.describe ApplicationController, type: :controller do
  controller do
    def index
      render inertia: "Dummy", props: { hello: "world" }
    end
  end

  before do
    routes.draw { get "index" => "anonymous#index" }
    # Inertia returns JSON only when the X-Inertia header is set; otherwise
    # it returns the HTML shell. Setting it here exercises the props pathway.
    request.headers["X-Inertia"] = "true"
  end

  describe "ai_provider inertia share" do
    {
      "gemini" => "Gemini",
      "openai" => "OpenAI",
      "ollama" => "Ollama",
    }.each do |provider, expected_label|
      it "exposes ai_provider='#{provider}' and ai_provider_label='#{expected_label}'" do
        allow(AiClient).to receive(:provider).and_return(provider)
        get :index
        json = JSON.parse(response.body)
        expect(json.dig("props", "ai_provider")).to eq(provider)
        expect(json.dig("props", "ai_provider_label")).to eq(expected_label)
      end
    end

    it "falls back to a capitalized label for unknown providers" do
      allow(AiClient).to receive(:provider).and_return("anthropic")
      get :index
      json = JSON.parse(response.body)
      expect(json.dig("props", "ai_provider")).to eq("anthropic")
      expect(json.dig("props", "ai_provider_label")).to eq("Anthropic")
    end

    it "still passes through page-specific props" do
      allow(AiClient).to receive(:provider).and_return("gemini")
      get :index
      json = JSON.parse(response.body)
      expect(json.dig("props", "hello")).to eq("world")
    end
  end
end
