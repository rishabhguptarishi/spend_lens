# frozen_string_literal: true

# Uses the configured AI provider (Ollama/Gemini/OpenAI) to extract transactions
# from bank statement text. Handles any format - CSV, PDF text, or raw content.
class AiStatementExtractorService
  CREDIT_KEYWORDS = StatementParsing::CreditKeywords::REGEX

  MAX_CONTENT_LENGTH = 12_000 # ~3k tokens, leave room for prompt + response

  def initialize(statement)
    @statement = statement
    @bank_account = statement.bank_account
    @user = @bank_account.user
  end

  def call
    return [] unless @statement.file.attached?

    transactions = extract_transactions
    return [] if transactions.blank?

    create_transactions(transactions)
    @statement.update!(status: 'parsed')
    transactions
  rescue => e
    Rails.logger.warn "AI extraction failed (#{e.class}): #{e.message}"
    []
  end

  # Extract transactions without saving (used by hybrid parser).
  def extract_transactions(preprocessed_content = nil)
    content = preprocessed_content.presence || extract_text_from_file
    return [] if content.blank?

    raw = extract_with_ai(content)
    raw.filter_map do |tx|
      normalized = StatementParsing::TransactionValidator.normalize(
        date: tx[:date],
        description: tx[:description],
        amount: tx[:amount],
        transaction_type: tx[:type],
        source: 'ai'
      )
      normalized if StatementParsing::TransactionValidator.valid?(normalized)
    end
  rescue => e
    Rails.logger.warn "AI extract_transactions failed: #{e.message}"
    []
  end

  private

  def extract_text_from_file
    file = @statement.file.download
    ext = @statement.file.filename.to_s.downcase.split('.').last

    case ext
    when 'csv'
      csv_to_ai_friendly_text(file)
    when 'pdf'
      pdf_text = extract_pdf_text(file)
      pdf_text.present? ? pdf_to_ai_friendly_text(pdf_text) : nil
    else
      file.to_s
    end
  end

  # Convert CSV to a simpler line format for AI parsing (Date | Description | Amount | Type)
  def csv_to_ai_friendly_text(content)
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

    lines = rows.map do |row|
      date = row[date_col].to_s.strip
      desc = row[desc_col].to_s.strip
      next if date.blank?

      debit_val = debit_col ? row[debit_col].to_s.gsub(/[^\d.]/, '').to_f : 0
      credit_val = credit_col ? row[credit_col].to_s.gsub(/[^\d.]/, '').to_f : 0
      if debit_val.positive? || credit_val.positive?
        amt = debit_val.positive? ? debit_val : credit_val
        type = credit_val.positive? ? 'credit' : 'debit'
      else
        amt = row[amt_col].to_s.gsub(/[^\d.]/, '').to_f
        type = amt.positive? ? 'debit' : 'credit' # Fallback: positive=debit, negative=credit in Indian exports
        amt = amt.abs
      end
      type = 'credit' if desc.match?(CREDIT_KEYWORDS) # Override: SALARY, A AINT, etc.
      next if amt < 0.01

      "#{date} | #{desc} | #{amt} | #{type}"
    end
    "Date | Description | Amount | Type\n" + lines.compact.join("\n")
  rescue => e
    Rails.logger.warn "CSV to text conversion failed: #{e.message}, using raw"
    content.to_s
  end

  def extract_pdf_text(content)
    require 'pdf-reader'
    reader = PDF::Reader.new(StringIO.new(content))
    text = reader.pages.map(&:text).join("\n")
    # If text extraction yields very little (scanned/image PDF), try OCR via pdftotext
    text = extract_pdf_via_ocr(content) if text.to_s.strip.length < 100 && reader.pages.size.positive?
    text
  rescue => e
    Rails.logger.warn "PDF extraction failed: #{e.message}"
    nil
  end

  # Convert PDF text to structured "Date | Description | Amount | Type" lines for AI parsing.
  # Uses same logic as the regex PDF parser so the AI gets clean, parseable input.
  def pdf_to_ai_friendly_text(text)
    skip_patterns = /\b(A\/C Open Date|Account Status|From\s*:|To\s*:|Statement of account|Page No\.?|Closing Balance|Contents of this statement|Registered Office)\b/i
    tx_date_regex = /^\s*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})\s+/
    tx_date_regex_alt = /\b(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{2,4})\b/i

    lines = text.split("\n")
    output_lines = []
    current_tx = nil

    lines.each do |line|
      next if line.blank?
      next if line.match?(skip_patterns)
      next if line.strip.match?(/^\d+\s*$/)

      date_match = line.match(tx_date_regex) || line.match(tx_date_regex_alt)
      if date_match
        if current_tx && current_tx[:amount] >= 0.01
          output_lines << "#{current_tx[:date_str]} | #{current_tx[:desc]} | #{current_tx[:amount]} | #{current_tx[:type]}"
        end

        date_str = date_match[1]
        rest = line[date_match.end(0)..].to_s
        amounts = rest.scan(/(\d{1,3}(?:,\d{3})*(?:\.\d{2})?)/).map { |a| a[0].gsub(',', '').to_f }
        amounts = amounts.select { |a| a >= 0.01 && a < 1e10 }

        amount = 0
        tx_type = 'debit'
        if amounts.size >= 2
          amount = amounts[-2]
          tx_type = rest[0..200].match?(CREDIT_KEYWORDS) ? 'credit' : 'debit'
        elsif amounts.size == 1
          amount = amounts[0]
          tx_type = if line.match?(/\b(?:Cr|Credit)\b/i) then 'credit'
                    elsif line.match?(/\b(?:Dr|Debit)\b/i) then 'debit'
                    else rest[0..200].match?(CREDIT_KEYWORDS) ? 'credit' : 'debit'
                    end
        end

        desc = rest.gsub(/\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}/, ' ')
          .gsub(/\d{1,3}(?:,\d{3})*(?:\.\d{2})?/, ' ')
          .gsub(/\d{15,}/, ' ')
          .gsub(/\s+/, ' ')
          .strip[0..200]
        desc = desc.presence || 'Unknown'
        tx_type = 'credit' if desc.match?(CREDIT_KEYWORDS)

        current_tx = { date_str: date_str, desc: desc, amount: amount, type: tx_type }
      elsif current_tx && line.strip.length.positive? && !line.match?(/^\s*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}/)
        current_tx[:desc] = "#{current_tx[:desc]} #{line.strip}"[0..200]
        current_tx[:type] = 'credit' if current_tx[:desc].match?(CREDIT_KEYWORDS)
      end
    end

    output_lines << "#{current_tx[:date_str]} | #{current_tx[:desc]} | #{current_tx[:amount]} | #{current_tx[:type]}" if current_tx && current_tx[:amount] >= 0.01

    return text if output_lines.empty? # Fall back to raw text if no structured lines found

    "Date | Description | Amount | Type\n" + output_lines.join("\n")
  rescue => e
    Rails.logger.warn "PDF to AI format failed: #{e.message}, using raw"
    text
  end

  def extract_pdf_via_ocr(content)
    return '' unless system('which', 'pdftotext', out: File::NULL, err: File::NULL)

    tmp = Tempfile.create(['stmt', '.pdf'])
    tmp.binmode
    tmp.write(content)
    tmp.flush
    tmp.close
    out = Tempfile.create(['stmt', '.txt'])
    out.close
    system('pdftotext', '-layout', tmp.path, out.path, out: File::NULL, err: File::NULL)
    File.read(out.path).force_encoding('UTF-8')
  rescue => e
    Rails.logger.warn "PDF OCR fallback failed: #{e.message}"
    ''
  end

  def extract_with_ai(content)
    truncated = content.truncate(MAX_CONTENT_LENGTH, omission: "\n... [truncated]")
    prompt = build_prompt(truncated)

    response = call_ollama(prompt)
    parsed = parse_ai_response(response)
    if parsed.blank? && response.present?
      Rails.logger.warn "AI extraction returned empty. Response preview: #{response.to_s.strip[0..800]}"
    end
    parsed
  rescue => e
    Rails.logger.error "AI extraction failed: #{e.message}"
    []
  end

  def build_prompt(content)
    <<~PROMPT
      Convert each line below to JSON. Return ONLY a valid JSON array. No markdown, no explanation.

      Format: [{"date":"YYYY-MM-DD","description":"string","amount":number,"type":"debit" or "credit"}]
      - date: Convert to YYYY-MM-DD (05/02/26 → 2026-02-05, 25=2025, 26=2026)
      - amount: positive number
      - type: use the type from each line (debit or credit)

      Example: [{"date":"2025-04-07","description":"UPI-SWIGGY","amount":869,"type":"debit"},{"date":"2025-04-06","description":"SALARY","amount":50000,"type":"credit"}]

      Input (each line: Date | Description | Amount | Type):
      #{content}
    PROMPT
  end

  def call_ollama(prompt)
    return '' unless @user.user_preference.ai_enabled?

    prefs = @user.user_preference
    client = Ollama.new(credentials: { address: prefs.ollama_url })
    response = client.chat(
      { model: prefs.ollama_model,
        messages: [{ role: 'user', content: prompt }],
        stream: false,
        format: 'json',
        options: { temperature: 0 } }
    )

    result = response.is_a?(Array) ? response.last : response
    result.dig('message', 'content') || ''
  end

  def parse_ai_response(response)
    json_str = response.to_s.strip
    # Strip markdown code blocks
    if json_str.include?('```')
      json_str = json_str[/```(?:json)?\s*([\s\S]*?)```/, 1] || json_str
    end
    json_str = json_str.strip
    # Try to extract array from response (model might add text before/after)
    if (m = json_str.match(/\[[\s\S]*\]/))
      json_str = m[0]
    end

    # Fix common JSON issues from LLMs (trailing commas, etc.)
    json_str = json_str.gsub(/,(\s*[}\]])/, '\1')
    data = JSON.parse(json_str)
    # Handle {"transactions": [...]} or {"data": [...]} wrapper
    data = data['transactions'] || data['data'] || data if data.is_a?(Hash)
    return [] unless data.is_a?(Array)

    data.filter_map do |item|
      next unless item.is_a?(Hash)

      desc = (item['description'] || item['desc'] || item['narration']).to_s.strip.presence || 'Unknown'
      type = (item['type'] || item['transaction_type']).to_s.downcase.include?('credit') ? 'credit' : 'debit'
      # Override: description credit keywords (SALARY, A AINT, etc.) = credit
      type = 'credit' if desc.match?(CREDIT_KEYWORDS)

      raw_amt = (item['amount'] || item['amt']).to_s.gsub(/[^\d.]/, '').to_f.abs
      next if raw_amt < 0.01 # Skip tiny/zero amounts

      {
        date: parse_date(item['date'] || item['transaction_date']),
        description: desc,
        amount: raw_amt,
        type: type,
      }
    end
  rescue JSON::ParserError => e
    Rails.logger.warn "AI JSON parse failed: #{e.message}. Response preview: #{response.to_s[0..200]}"
    []
  end

  def parse_date(str)
    return Date.current if str.blank?

    str = str.to_s.strip
    # DD/MM/YY or DD/MM/YYYY
    if str.match?(%r{\A(\d{1,2})/(\d{1,2})/(\d{2,4})\z})
      day, month, yy = str.split('/').map(&:to_i)
      year = yy < 100 ? (yy >= 50 ? 1900 + yy : 2000 + yy) : yy
      return Date.new(year, month, day)
    end
    # DD-MM-YY or DD-MM-YYYY
    if str.match?(%r{\A(\d{1,2})-(\d{1,2})-(\d{2,4})\z})
      day, month, yy = str.split('-').map(&:to_i)
      year = yy < 100 ? (yy >= 50 ? 1900 + yy : 2000 + yy) : yy
      return Date.new(year, month, day)
    end
    # YYYY-MM-DD (ISO)
    if str.match?(/\A(\d{4})-(\d{1,2})-(\d{1,2})\z/)
      year, month, day = str.split('-').map(&:to_i)
      return Date.new(year, month, day)
    end

    Date.parse(str)
  rescue ArgumentError
    Date.current
  end

  def create_transactions(transactions)
    categorizer = TransactionCategorizationService.new(@user)
    merchant = nil

    transactions.each do |tx|
      next if tx[:amount].to_f.zero?

      merchant = tx[:description].to_s[0..100]
      type = tx[:transaction_type] || tx[:type]
      category = categorizer.categorize(tx[:description], merchant: merchant)
      is_recurring = RecurringTransactionDetector.new(@user).recurring?(tx[:description], tx[:amount], tx[:date])

      next if duplicate?(tx)

      @statement.transactions.create!(
        date: tx[:date],
        description: tx[:description],
        amount: tx[:amount],
        transaction_type: type,
        merchant: merchant,
        category: category,
        is_recurring: is_recurring
      )
    rescue => e
      Rails.logger.warn "Transaction create failed: #{e.message}"
    end
  end

  # Check across entire bank account to avoid duplicates when re-uploading same statement
  def duplicate?(tx)
    Transaction
      .joins(:statement)
      .where(statements: { bank_account_id: @bank_account.id })
      .exists?(
        date: tx[:date],
        amount: tx[:amount],
        description: tx[:description]
      )
  end
end
