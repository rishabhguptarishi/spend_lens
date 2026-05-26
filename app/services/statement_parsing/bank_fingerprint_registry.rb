# frozen_string_literal: true

module StatementParsing
  # Replaces the scattered `axis_statement?` / `icici_statement?`
  # boolean methods that used to live inside RegexExtractor with a
  # data-driven registry. Per docs/INVESTMENT_ARCHITECTURE.html §4.2.
  #
  # Each entry registers ONE bank:
  #
  #   - name              => human display name ("ICICI Bank")
  #   - ifsc_prefix       => the IFSC's first 4 chars ("ICIC0", "HDFC0"); used
  #                          first because it never has false-positives
  #   - header_patterns   => array of regex that match somewhere in the first
  #                          ~80 lines of extracted text (URLs, bank names,
  #                          unique column headers)
  #   - parser            => parser class (must respond to .parse(content))
  #   - features          => Array<Symbol> of capability flags the parser
  #                          opts into (e.g. :multi_account_sections,
  #                          :portfolio_extraction)
  #
  # Lookup order: caller passes the raw extracted text. Registry tries
  # IFSC-prefix match first (cheapest + most accurate), then each entry's
  # header_patterns in registration order. First match wins.
  #
  # Returns nil when nothing matches — the caller (StatementParserService)
  # then falls through to the generic RegexExtractor as today.
  module BankFingerprintRegistry
    Entry = Struct.new(:name, :ifsc_prefix, :header_patterns, :parser, :features, :sample_path, keyword_init: true) do
      def matches?(text)
        return true if ifsc_prefix.present? && text.match?(/\b#{Regexp.escape(ifsc_prefix)}\w{4,}\b/)

        head = text.to_s.lines.first(80).join("\n")
        Array(header_patterns).any? { |p| head.match?(p) }
      end
    end

    @entries = []

    class << self
      # Register a bank. Idempotent: re-registering the same `name` replaces
      # the previous entry (useful in spec setup / Rails reloader).
      def register(name, **attrs)
        entry = Entry.new(name: name, **attrs.slice(:ifsc_prefix, :header_patterns, :parser, :features, :sample_path))
        @entries.reject! { |e| e.name == name }
        @entries << entry
        entry
      end

      # Returns the first registered Entry whose fingerprint matches the
      # given text, or nil if none match.
      def detect(text)
        return nil if text.blank?

        @entries.find { |e| e.matches?(text) }
      end

      def lookup(name)
        @entries.find { |e| e.name == name }
      end

      def all
        @entries.dup
      end

      # Mostly for tests / reloader hooks. NOT called at runtime.
      def reset!
        @entries.clear
      end
    end
  end
end
