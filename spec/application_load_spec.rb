# frozen_string_literal: true

require "rails_helper"

# Smoke test: force every class in the autoload paths to load.
#
# Catches an entire class of bugs:
#   - NameError: filename / classname mismatches (Zeitwerk autoload failures)
#   - Constants referenced inside one file but defined inside a non-matching
#     file (e.g. `StatementParsing::CREDIT_KEYWORDS` was defined inside
#     `credit_keywords.rb` without a matching `CreditKeywords` class — broke
#     autoload silently until someone called it)
#   - Missing requires, syntax errors, circular dependencies
#
# If this spec fails, the dev server may *seem* to boot but some code paths
# will explode at first call. Keep this green.
RSpec.describe "Application eager-load", type: :smoke do
  it "loads every class in the autoload paths without errors" do
    expect { Rails.application.eager_load! }.not_to raise_error
  end

  describe "expected modules and helpers are defined after eager-loading" do
    before { Rails.application.eager_load! }

    it "defines the StatementParsing namespace with .credit? helper" do
      expect(defined?(StatementParsing)).to eq("constant")
      expect(StatementParsing).to respond_to(:credit?)
    end

    it "defines StatementParsing::CreditKeywords with REGEX + .match?" do
      expect(defined?(StatementParsing::CreditKeywords)).to eq("constant")
      expect(StatementParsing::CreditKeywords::REGEX).to be_a(Regexp)
      expect(StatementParsing::CreditKeywords).to respond_to(:match?)
    end

    it "defines the parsing pipeline classes" do
      %w[
        RegexExtractor
        TextExtractor
        AiPreprocessor
        TransactionValidator
        TransactionMerger
        Persister
      ].each do |klass|
        expect(StatementParsing.const_defined?(klass)).to be(true), "missing StatementParsing::#{klass}"
      end
    end

    it "defines the AI namespace with the agent loop service" do
      expect(defined?(Ai::AgenticChatService)).to eq("constant")
    end

    it "defines the AiClient service" do
      expect(defined?(AiClient)).to eq("constant")
      expect(AiClient).to respond_to(:chat)
      expect(AiClient).to respond_to(:chat_with_tools)
    end
  end
end
