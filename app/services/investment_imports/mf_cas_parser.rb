# frozen_string_literal: true

module InvestmentImports
  # MF Consolidated Account Statement — regex + optional AI fallback.
  class MfCasParser < BaseParser
    TXN_LINE = /
      (?<date>\d{1,2}[-\/]\w{3}[-\/]\d{2,4}|\d{4}-\d{2}-\d{2})
      .{0,80}?
      (?<kind>Purchase|Redemption|SIP|Switch|Dividend|IDCW)
      .{0,60}?
      (?<amount>[\d,]+\.?\d*)
    /ix

    def parse
      text = @content.is_a?(String) ? @content : @content.to_s
      rows = parse_regex(text)
      rows = parse_ai(text) if rows.size < 3 && text.length > 200
      rows.compact
    end

    private

    def parse_regex(text)
      current_scheme = nil
      out = []

      text.each_line do |line|
        if line.match?(/folio|scheme|fund/i) && line.length < 120
          current_scheme = line.strip.gsub(/\s+/, ' ')[0..80]
        end

        m = line.match(TXN_LINE)
        next unless m

        kind = map_kind(m[:kind])
        out << row(
          date: m[:date],
          kind: kind,
          amount: m[:amount].to_s.delete(','),
          description: current_scheme || 'MF CAS',
          asset_class: 'mutual_fund'
        )
      end
      out
    end

    def map_kind(raw)
      case raw.to_s.downcase
      when /redemption/ then 'sell'
      when /purchase|sip/ then 'buy'
      when /dividend|idcw/ then 'dividend'
      else 'other'
      end
    end

    def parse_ai(text)
      client = Ollama.new(credentials: { address: ENV.fetch('OLLAMA_URL', 'http://localhost:11434') })
      prompt = <<~PROMPT
        Extract mutual fund transactions from this CAS text. Return ONLY a JSON array:
        [{"date":"YYYY-MM-DD","kind":"buy|sell|dividend","amount":1234.56,"description":"scheme name"}]
        Text:
        #{text[0..8000]}
      PROMPT
      response = client.chat(
        model: ENV.fetch('OLLAMA_MODEL', 'llama3.2'),
        messages: [{ role: 'user', content: prompt }],
        stream: false
      )
      result = response.is_a?(Array) ? response.last : response
      content = result.dig('message', 'content').to_s
      json = content[/\[[\s\S]*\]/]
      return [] unless json

      JSON.parse(json).filter_map do |tx|
        row(
          date: tx['date'],
          kind: tx['kind'],
          amount: tx['amount'],
          description: tx['description'],
          asset_class: 'mutual_fund'
        )
      end
    rescue => e
      Rails.logger.warn "MF CAS AI parse failed: #{e.message}"
      []
    end
  end
end
