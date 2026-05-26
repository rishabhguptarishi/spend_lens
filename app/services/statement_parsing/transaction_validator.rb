# frozen_string_literal: true

module StatementParsing
  # Layer 4: Validate and filter parsed transaction hashes before save.
  class TransactionValidator
    GENERIC_DESCRIPTION = /\A(transaction\s*\d+|test\s*transaction)\z/i
    MIN_DESCRIPTION_LENGTH = 2
    MAX_AMOUNT = 50_000_000
    MIN_AMOUNT = 0.01
    MAX_PAST_YEARS = 15
    MAX_FUTURE_DAYS = 7

    def self.validate_all(transactions)
      Array(transactions).filter_map do |tx|
        normalized = normalize(tx)
        normalized if valid?(normalized)
      end
    end

    def self.valid?(tx)
      return false if tx.blank?
      return false if tx[:amount].to_f < MIN_AMOUNT || tx[:amount].to_f > MAX_AMOUNT
      return false if tx[:description].to_s.strip.length < MIN_DESCRIPTION_LENGTH
      return false if tx[:description].to_s.match?(GENERIC_DESCRIPTION)
      return false unless valid_date?(tx[:date])

      true
    end

    def self.normalize(tx)
      desc = tx[:description].to_s.strip[0..200]
      type = tx[:transaction_type] || tx[:type]
      type = 'credit' if StatementParsing.credit?(desc)
      type = type.to_s.downcase.include?('credit') ? 'credit' : 'debit'

      {
        date: tx[:date].is_a?(Date) ? tx[:date] : parse_date(tx[:date]),
        description: desc.presence || 'Unknown',
        amount: tx[:amount].to_f.abs,
        transaction_type: type,
        source: tx[:source] || 'unknown',
      }
    end

    def self.valid_date?(date)
      return false if date.blank?
      d = date.is_a?(Date) ? date : parse_date(date)
      return false if d.blank?

      d >= MAX_PAST_YEARS.years.ago.to_date && d <= MAX_FUTURE_DAYS.days.from_now.to_date
    rescue ArgumentError
      false
    end

    def self.parse_date(str)
      return str if str.is_a?(Date)
      return nil if str.blank?

      s = str.to_s.strip
      if s.match?(%r{\A(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})\z})
        day, month, yy = s.split(%r{[/\-]}).map(&:to_i)
        year = yy < 100 ? (yy >= 50 ? 1900 + yy : 2000 + yy) : yy
        return Date.new(year, month, day)
      end
      if s.match?(/\A(\d{4})-(\d{1,2})-(\d{1,2})\z/)
        year, month, day = s.split('-').map(&:to_i)
        return Date.new(year, month, day)
      end

      Date.parse(s)
    rescue ArgumentError
      nil
    end

    def self.ai_batch_trustworthy?(ai_list, regex_list)
      return true if ai_list.blank?
      return false if regex_list.size >= 20 && ai_list.size < [5, regex_list.size / 10].max

      generic_count = ai_list.count { |t| t[:description].to_s.match?(GENERIC_DESCRIPTION) }
      generic_count < ai_list.size / 2
    end
  end
end
