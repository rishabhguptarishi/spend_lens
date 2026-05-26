# frozen_string_literal: true

module StatementParsing
  # Layer 2b: Structure PDF/CSV text for AI input (same rules as regex line parser).
  class AiPreprocessor
    def self.prepare(content, format:)
      case format.to_sym
      when :csv
        csv_to_lines(content)
      when :pdf
        pdf_to_lines(content)
      else
        content.to_s
      end
    end

    def self.csv_to_lines(content)
      require 'csv'
      content = content.force_encoding('UTF-8')
      rows = CSV.parse(content, headers: true, liberal_parsing: true)
      return content.to_s if rows.empty?

      headers = rows.first.to_h.keys.map(&:to_s)
      date_col = headers.find { |h| h.downcase.include?('date') } || headers[0]
      desc_col = headers.find { |h| h.downcase.match?(/desc|particular|narrative|memo/) } || headers[1]
      debit_col = headers.find { |h| h.downcase == 'debit' }
      credit_col = headers.find { |h| h.downcase == 'credit' }
      amt_col = headers.find { |h| h.downcase.match?(/amount|amt/) } || headers[-1]

      lines = rows.filter_map do |row|
        date = row[date_col].to_s.strip
        desc = row[desc_col].to_s.strip
        next if date.blank?

        debit_val = debit_col ? row[debit_col].to_s.gsub(/[^\d.]/, '').to_f : 0
        credit_val = credit_col ? row[credit_col].to_s.gsub(/[^\d.]/, '').to_f : 0
        if debit_val.positive? || credit_val.positive?
          amt = debit_val.positive? ? debit_val : credit_val
          type = credit_val.positive? ? 'credit' : 'debit'
        else
          amt = row[amt_col].to_s.gsub(/[^\d.]/, '').to_f.abs
          type = amt.positive? ? 'debit' : 'credit'
        end
        type = 'credit' if StatementParsing.credit?(desc)
        next if amt < 0.01

        "#{date} | #{desc} | #{amt} | #{type}"
      end

      "Date | Description | Amount | Type\n" + lines.join("\n")
    rescue => e
      Rails.logger.warn "AI preprocess CSV failed: #{e.message}"
      content.to_s
    end

    def self.pdf_to_lines(text)
      extractor = RegexExtractor.new(content: text, format: :pdf)
      txs = extractor.call
      return text if txs.empty?

      lines = txs.map do |tx|
        date_str = tx[:date].strftime('%d/%m/%Y')
        "#{date_str} | #{tx[:description]} | #{tx[:amount]} | #{tx[:transaction_type]}"
      end
      "Date | Description | Amount | Type\n" + lines.join("\n")
    end
  end
end
