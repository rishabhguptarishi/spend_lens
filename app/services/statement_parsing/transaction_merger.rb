# frozen_string_literal: true

module StatementParsing
  # Layer 4: Merge regex + AI results, dedupe, prefer regex on conflicts.
  class TransactionMerger
    def self.merge(regex_list, ai_list, trust_ai: true)
      regex_list = TransactionValidator.validate_all(regex_list)
      ai_list = trust_ai ? TransactionValidator.validate_all(ai_list) : []

      combined = regex_list + ai_list
      return regex_list if combined.empty?

      by_key = {}
      combined.each do |tx|
        key = dedupe_key(tx)
        existing = by_key[key]
        by_key[key] = existing ? prefer(existing, tx) : tx
      end

      by_key.values.sort_by { |t| [t[:date], -t[:amount]] }
    end

    def self.dedupe_key(tx)
      desc = tx[:description].to_s.downcase.gsub(/\s+/, ' ').strip[0..80]
      [tx[:date], tx[:amount].round(2), desc]
    end

    def self.prefer(a, b)
      # Regex parser is more reliable for Indian bank PDF layouts
      return a if a[:source] == 'regex' && b[:source] != 'regex'
      return b if b[:source] == 'regex' && a[:source] != 'regex'

      # Prefer credit classification when keywords present
      a_credit = StatementParsing.credit?(a[:description])
      b_credit = StatementParsing.credit?(b[:description])
      return a if a_credit && b[:transaction_type] == 'debit'
      return b if b_credit && a[:transaction_type] == 'debit'

      # Prefer longer description (more detail from statement)
      a[:description].to_s.length >= b[:description].to_s.length ? a : b
    end
  end
end
