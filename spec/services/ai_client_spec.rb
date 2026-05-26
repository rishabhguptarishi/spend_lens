# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiClient, type: :service do
  before do
    # Clear env vars before each test to prevent pollution
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).and_call_original
  end

  describe ".chat" do
    let(:prompt) { "Hello, testing LLM integration" }

    context "when AI_PROVIDER is gemini" do
      before do
        allow(ENV).to receive(:fetch).with("AI_PROVIDER", "ollama").and_return("gemini")
        allow(ENV).to receive(:[]).with("GEMINI_API_KEY").and_return("test_gemini_key")
        allow(ENV).to receive(:fetch).with("GEMINI_MODEL", "gemini-2.5-flash").and_return("gemini-2.5-flash")
      end

      it "calls Gemini API and parses the response successfully" do
        gemini_response_body = {
          candidates: [{
            content: {
              parts: [{ text: "Gemini generated answer" }]
            }
          }]
        }.to_json

        stub_request(:post, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=test_gemini_key")
          .with(
            headers: { "Content-Type" => "application/json" },
            body: { contents: [{ parts: [{ text: prompt }] }] }.to_json
          )
          .to_return(status: 200, body: gemini_response_body, headers: {})

        result = described_class.chat(prompt)
        expect(result).to eq("Gemini generated answer")
      end

      it "configures JSON response format when requested" do
        gemini_response_body = {
          candidates: [{
            content: {
              parts: [{ text: '{"result": "success"}' }]
            }
          }]
        }.to_json

        stub_request(:post, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=test_gemini_key")
          .with(
            body: hash_including(
              generationConfig: { responseMimeType: "application/json" }
            )
          )
          .to_return(status: 200, body: gemini_response_body)

        result = described_class.chat(prompt, format: "json")
        expect(result).to eq('{"result": "success"}')
      end

      it "raises an error if GEMINI_API_KEY is missing" do
        allow(ENV).to receive(:[]).with("GEMINI_API_KEY").and_return(nil)
        expect { described_class.chat(prompt) }.to raise_error(/GEMINI_API_KEY is not configured/)
      end

      it "honors a custom GEMINI_MODEL value" do
        allow(ENV).to receive(:fetch).with("GEMINI_MODEL", "gemini-2.5-flash").and_return("gemini-2.0-flash")

        stub_request(:post, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=test_gemini_key")
          .to_return(status: 200, body: { candidates: [{ content: { parts: [{ text: "ok" }] } }] }.to_json)

        expect(described_class.chat(prompt)).to eq("ok")
      end
    end

    context "provider helpers" do
      it "reports the configured provider" do
        allow(ENV).to receive(:fetch).with("AI_PROVIDER", "ollama").and_return("gemini")
        expect(described_class.provider).to eq("gemini")
      end

      it "treats unset AI_PROVIDER as ollama" do
        allow(ENV).to receive(:fetch).with("AI_PROVIDER", "ollama").and_return("ollama")
        expect(described_class.provider).to eq("ollama")
      end

      it "advertises gemini and openai as agentic-capable providers" do
        allow(ENV).to receive(:fetch).with("AI_PROVIDER", "ollama").and_return("gemini")
        expect(described_class.agentic_supported?).to be true

        allow(ENV).to receive(:fetch).with("AI_PROVIDER", "ollama").and_return("openai")
        expect(described_class.agentic_supported?).to be true

        allow(ENV).to receive(:fetch).with("AI_PROVIDER", "ollama").and_return("ollama")
        expect(described_class.agentic_supported?).to be false
      end

      it "raises NotImplementedError when ollama is used for tool calls" do
        allow(ENV).to receive(:fetch).with("AI_PROVIDER", "ollama").and_return("ollama")
        expect { described_class.chat_with_tools([], tools: []) }
          .to raise_error(NotImplementedError, /does not support agentic tool calling/)
      end
    end

    context "when AI_PROVIDER is openai" do
      before do
        allow(ENV).to receive(:fetch).with("AI_PROVIDER", "ollama").and_return("openai")
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test_openai_key")
        allow(ENV).to receive(:fetch).with("OPENAI_MODEL", "gpt-4o-mini").and_return("gpt-4o-mini")
        allow(ENV).to receive(:fetch).with("OPENAI_API_URL", "https://api.openai.com/v1/chat/completions").and_return("https://api.openai.com/v1/chat/completions")
      end

      it "calls OpenAI API and returns choices content" do
        openai_response_body = {
          choices: [{
            message: { role: "assistant", content: "OpenAI generated answer" }
          }]
        }.to_json

        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .with(
            headers: {
              "Content-Type" => "application/json",
              "Authorization" => "Bearer test_openai_key"
            },
            body: {
              model: "gpt-4o-mini",
              messages: [{ role: "user", content: prompt }]
            }.to_json
          )
          .to_return(status: 200, body: openai_response_body)

        result = described_class.chat(prompt)
        expect(result).to eq("OpenAI generated answer")
      end

      it "appends response format for json when requested" do
        openai_response_body = {
          choices: [{
            message: { role: "assistant", content: '{"status": "ok"}' }
          }]
        }.to_json

        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .with(
            body: hash_including(
              response_format: { type: "json_object" }
            )
          )
          .to_return(status: 200, body: openai_response_body)

        result = described_class.chat(prompt, format: "json")
        expect(result).to eq('{"status": "ok"}')
      end

      it "raises an error if OPENAI_API_KEY is missing" do
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)
        expect { described_class.chat(prompt) }.to raise_error(/OPENAI_API_KEY is not configured/)
      end
    end

    context "when AI_PROVIDER is ollama (or default)" do
      let(:user_pref) { double("UserPreference", ollama_url: "http://localhost:11434", ollama_model: "llama3.2") }

      before do
        allow(ENV).to receive(:fetch).with("AI_PROVIDER", "ollama").and_return("ollama")
        allow(ENV).to receive(:fetch).with("OLLAMA_URL", "http://localhost:11434").and_return("http://localhost:11434")
        allow(ENV).to receive(:fetch).with("OLLAMA_MODEL", "llama3.2").and_return("llama3.2")
      end

      it "instantiates Ollama client and forwards the prompt" do
        ollama_response = { "message" => { "content" => "Ollama generated answer" } }
        
        # Stub the local Ollama HTTP request
        stub_request(:post, "http://localhost:11434/api/chat")
          .to_return(status: 200, body: ollama_response.to_json)

        result = described_class.chat(prompt, user_pref)
        expect(result).to eq("Ollama generated answer")
      end
    end
  end
end
