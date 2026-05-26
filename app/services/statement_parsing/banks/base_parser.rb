# frozen_string_literal: true

module StatementParsing
  module Banks
    # Abstract base for per-bank statement parsers.
    #
    # Why this exists: the legacy RegexExtractor handled every bank via
    # an in-class layout switch (axis / icici / other). This baked
    # bank-specific knowledge into one ~400-line class and made parser
    # versioning, regression suites, and "drift detected" telemetry
    # impossible. Per docs/INVESTMENT_ARCHITECTURE.html §4.4, every bank
    # now lives in its own subclass that:
    #
    #   - Carries a VERSION constant so we can spot regressions when a
    #     bank changes layout (banks ship 1-2 layout changes / year).
    #   - Records EXTRACTION_METHOD ∈ %w[deterministic table ai_text ocr
    #     vision_llm] so downstream services know what to trust.
    #   - Returns a structured ParseResult instead of a bare Array, so
    #     the caller (StatementParserService) can grab opening/closing
    #     balances for the BalanceVerifier and persist parse_quality.
    #
    # Subclasses MUST implement #parse_pdf (and may override #parse_csv
    # when a bank has a quirky CSV layout). Default CSV path delegates
    # to the format-agnostic RegexExtractor since CSV is structured
    # enough that one parser handles every bank.
    class BaseParser
      VERSION = '2026.05'
      EXTRACTION_METHOD = 'deterministic'

      # All subclasses share this header to identify themselves.
      def self.bank_name
        raise NotImplementedError, "#{self} must define .bank_name"
      end

      def initialize(content:, format: :pdf)
        @content = content
        @format = format.to_sym
      end

      # Public entry point. Returns ParseResult.
      def call
        transactions =
          case @format
          when :csv then parse_csv
          when :pdf then parse_pdf
          else []
          end

        opening = extract_opening_balance
        closing = extract_closing_balance

        ParseResult.new(
          transactions: transactions,
          opening_balance: opening,
          closing_balance: closing,
          parser_name: self.class.bank_name,
          parser_version: self.class::VERSION,
          extraction_method: self.class::EXTRACTION_METHOD,
        )
      end

      protected

      def parse_csv
        RegexExtractor.new(content: @content, format: :csv).call
      end

      # Per-bank PDF strategy. Default delegates to the legacy
      # RegexExtractor which still contains the unified regex loop
      # (with internal :axis / :icici / :other branching). Subclasses
      # currently piggy-back on that path so this refactor is purely
      # additive — no behavioural change. Future per-bank PRs replace
      # this with a bank-specific implementation as needed.
      def parse_pdf
        RegexExtractor.new(content: @content, format: :pdf).call
      end

      # Default opening-balance extractor. Most Tier-1 banks print the
      # phrase "Opening Balance" in their header. Subclasses can
      # override when their header uses a different wording.
      def extract_opening_balance
        match = @content.to_s.match(/Opening\s+Balance[^\d]+([\d,]+\.\d{1,2})/i)
        return nil unless match

        match[1].gsub(',', '').to_f
      end

      def extract_closing_balance
        match = @content.to_s.match(/Closing\s+Balance[^\d]+([\d,]+\.\d{1,2})/i)
        return nil unless match

        match[1].gsub(',', '').to_f
      end
    end

    # Plain value object emitted by every bank parser. Kept here rather
    # than in its own file because no other consumer instantiates it.
    ParseResult = Struct.new(
      :transactions,
      :opening_balance,
      :closing_balance,
      :parser_name,
      :parser_version,
      :extraction_method,
      keyword_init: true,
    ) do
      def to_h
        {
          transactions: transactions,
          opening_balance: opening_balance,
          closing_balance: closing_balance,
          parser_name: parser_name,
          parser_version: parser_version,
          extraction_method: extraction_method,
        }
      end
    end
  end
end
