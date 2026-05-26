# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::AgenticChatService, type: :service do
  let(:user) { make_user }

  describe ".enabled?" do
    it "returns true when ENV defaults and AiClient supports tool calling" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("AI_AGENTIC_ENABLED", "true").and_return("true")
      allow(AiClient).to receive(:agentic_supported?).and_return(true)
      expect(described_class.enabled?).to be true
    end

    it "returns false when AI_AGENTIC_ENABLED is 'false'" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("AI_AGENTIC_ENABLED", "true").and_return("false")
      allow(AiClient).to receive(:agentic_supported?).and_return(true)
      expect(described_class.enabled?).to be false
    end

    it "returns false when AiClient.agentic_supported? is false" do
      allow(AiClient).to receive(:agentic_supported?).and_return(false)
      expect(described_class.enabled?).to be false
    end
  end

  describe "initialization" do
    it "coerces unknown modes to 'spending'" do
      svc = described_class.new(user, mode: "bogus", allow_writes: true)
      expect(svc.instance_variable_get(:@mode)).to eq("spending")
    end

    it "forces allow_writes=false when mode is 'itr'" do
      svc = described_class.new(user, mode: "itr", allow_writes: true)
      expect(svc.instance_variable_get(:@allow_writes)).to be false
    end
  end

  describe "#run" do
    before do
      allow(described_class).to receive(:enabled?).and_return(true)
      allow(AiClient).to receive(:provider).and_return("gemini")
    end

    context "when the LLM returns a final answer immediately" do
      it "returns the text as the Result.answer" do
        allow(AiClient).to receive(:chat_with_tools).and_return({ text: "All clear.", tool_calls: [] })
        result = described_class.new(user).run("how am I doing?")
        expect(result).to be_a(described_class::Result)
        expect(result.answer).to eq("All clear.")
        expect(result.tool_trail).to eq([])
        expect(result.proposals).to eq([])
      end
    end

    context "when the LLM calls a read tool then answers" do
      it "executes the tool, appends an observation, and returns answer + tool_trail" do
        responses = [
          { text: nil, tool_calls: [{ id: "1", name: "list_categories", args: {} }] },
          { text: "You have several categories.", tool_calls: [] },
        ]
        allow(AiClient).to receive(:chat_with_tools) { responses.shift }

        result = described_class.new(user).run("list categories")
        expect(result.answer).to eq("You have several categories.")
        expect(result.tool_trail.first[:name]).to eq("list_categories")
        expect(result.proposals).to eq([])
      end
    end

    context "when a write tool returns a proposal" do
      it "collects the proposal into Result.proposals" do
        responses = [
          { text: nil, tool_calls: [{ id: "1", name: "propose_create_category", args: { name: "Subs" } }] },
          { text: "Drafted a proposal.", tool_calls: [] },
        ]
        allow(AiClient).to receive(:chat_with_tools) { responses.shift }

        result = described_class.new(user, allow_writes: true).run("add a Subs category")
        expect(result.proposals.size).to eq(1)
        expect(result.proposals.first[:kind]).to eq("create_category")
      end
    end

    context "when an unknown tool is requested" do
      it "treats it as an error observation and continues" do
        responses = [
          { text: nil, tool_calls: [{ id: "1", name: "no_such_tool", args: {} }] },
          { text: "Sorry, can't help.", tool_calls: [] },
        ]
        allow(AiClient).to receive(:chat_with_tools) { responses.shift }

        result = described_class.new(user).run("?")
        expect(result.answer).to eq("Sorry, can't help.")
        expect(result.tool_trail.first[:result_preview]).to include("unknown tool")
      end
    end

    context "when a tool raises a ToolError" do
      it "captures the error message in the observation without crashing" do
        responses = [
          { text: nil, tool_calls: [{ id: "1", name: "search_transactions", args: {} }] },
          { text: "Need a query.", tool_calls: [] },
        ]
        allow(AiClient).to receive(:chat_with_tools) { responses.shift }

        result = described_class.new(user).run("search")
        expect(result.tool_trail.first[:result_preview]).to match(/query/i)
      end
    end

    context "when agentic mode is disabled" do
      it "raises AgenticDisabledError from #run" do
        allow(described_class).to receive(:enabled?).and_return(false)
        expect { described_class.new(user).run("?") }
          .to raise_error(described_class::AgenticDisabledError)
      end
    end
  end
end
