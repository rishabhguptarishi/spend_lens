# frozen_string_literal: true

# Extracts bank account info and statement period from statement content using AI.
# Used to auto-create bank accounts and auto-detect month/year.
class StatementMetadataExtractorService
  MAX_CONTENT_LENGTH = 6_000 # Indian bank PDFs often print account info on page 2

  # Labels that contain the most important identification fields. We hoist
  # every line matching these into the AI prompt so SBI/HDFC layouts that
  # bury "Account Number" on page 2 still surface the value within the AI
  # context window.
  KEY_LINE_RE = /\b(Account\s+(?:Number|No\.?)|A\/c\s+(?:No\.?|Number)|IFSC\s+Code|Customer\s+ID|CIF\s+Number|Branch(?:\s+Name)?|Product|Statement(?:\s+(?:From|Period|Date|of\s+Account))?|Currency|Account\s+Type|Card\s+Number|Card\s+ending)\b/i

  def initialize(file_content, filename: nil)
    @content = String.new(file_content.to_s).force_encoding('UTF-8')
    @filename = filename
  end

  def call
    # We always run BOTH extractors and merge — AI is good at semantic
    # fields (bank_name, account_type) while regex is the source of truth
    # for the literal account number (AI tends to confabulate "0000" when
    # the number isn't visible in its truncated view).
    ai_data    = (extract_with_ai || {}).transform_keys(&:to_s)
    regex_data = (extract_with_regex || {}).transform_keys(&:to_s)
    merged     = merge_metadata(ai_data, regex_data)

    return default_metadata if merged.values.all?(&:blank?)

    normalize_metadata(merged)
  rescue => e
    Rails.logger.warn "Metadata extraction failed: #{e.message}"
    default_metadata
  end

  private

  def merge_metadata(ai, rx)
    {
      'bank_name'         => prefer_bank_name(ai['bank_name'], rx['bank_name']),
      'account_last_four' => prefer_last_four(ai['account_last_four'], rx['account_last_four']),
      'account_type'      => prefer(ai['account_type'], rx['account_type']),
      'statement_month'   => prefer(ai['statement_month'], rx['statement_month']),
      'statement_year'    => prefer(ai['statement_year'], rx['statement_year']),
      'period_start'      => prefer(ai['period_start'], rx['period_start']),
      'period_end'        => prefer(ai['period_end'], rx['period_end']),
    }
  end

  def prefer(primary, secondary)
    primary.respond_to?(:blank?) && primary.blank? ? secondary : (primary || secondary)
  end

  # When the regex extractor found a name from BANK_FINGERPRINTS (which
  # are the canonical / expanded forms), prefer it over an AI-emitted
  # abbreviation like "SBI" or "HDFC" — same bank, but the long form is
  # what the UI shows on bank-account cards.
  def prefer_bank_name(ai_val, rx_val)
    return rx_val if rx_val.present? && BANK_FINGERPRINTS.any? { |_, name| name.casecmp?(rx_val) } && ai_val.to_s.strip.length < rx_val.length
    prefer(ai_val, rx_val)
  end

  # AI tends to fill account_last_four with "0000" (the prompt's "if
  # unknown" placeholder) when the number isn't in its truncated view.
  # The regex extractor reads the FULL document and finds the labeled
  # "Account Number : 35035715556" line — trust it over a placeholder.
  def prefer_last_four(ai_val, rx_val)
    ai_digits = ai_val.to_s.gsub(/\D/, '')
    rx_digits = rx_val.to_s.gsub(/\D/, '')

    if rx_digits.present? && rx_digits != '0000' && (ai_digits.blank? || ai_digits == '0000')
      return rx_val
    end

    ai_val.presence || rx_val
  end

  def extract_with_ai
    prompt = build_prompt(content_for_ai)

    response = call_ollama(prompt)
    parse_response(response)
  end

  # Smart truncation: send the first ~3.5KB of the statement (covers the
  # header for most banks) PLUS every line that matches a key label
  # anywhere in the document. This ensures multi-page PDFs whose account
  # number lives on page 2+ still fit inside the AI's context window.
  def content_for_ai
    head_budget = (MAX_CONTENT_LENGTH * 0.6).to_i
    head = @content[0, head_budget].to_s

    key_lines = @content.lines.select { |l| l.match?(KEY_LINE_RE) }.first(40).join.strip
    return head if key_lines.blank?

    digest = "#{head}\n--- KEY FIELDS ---\n#{key_lines}"
    digest[0, MAX_CONTENT_LENGTH]
  end

  def build_prompt(content)
    <<~PROMPT
      Extract bank metadata from this statement. Return ONLY valid JSON. No markdown, no explanation.

      Required format: {"bank_name":"string","account_last_four":"4 digits","account_type":"credit_card|debit_card|savings|current","statement_month":1-12,"statement_year":2024,"period_start":"YYYY-MM-DD","period_end":"YYYY-MM-DD"}

      Rules:
      - bank_name: Exact name from statement headers/first lines. If not found use "Unknown Bank"
      - account_last_four: Last 4 digits (e.g. 1234 from ••••1234). Use "0000" if unknown
      - account_type: credit_card, debit_card, savings, or current
      - statement_month: 1-12 — for full-FY statements, return the FIRST month of the covered period
      - statement_year: e.g. 2025 — pair with statement_month above
      - period_start / period_end: The actual statement period (ISO dates). For a March-only statement these would typically be 2025-03-01 and 2025-03-31. For a full FY statement 2025-04-01 and 2026-03-31. Use null if you cannot determine.

      Statement:
      #{content}
    PROMPT
  end

  def call_ollama(prompt)
    AiClient.chat(prompt, format: "json", temperature: 0)
  rescue => e
    Rails.logger.warn "AI metadata call failed: #{e.message}"
    nil
  end

  def parse_response(response)
    return nil if response.blank?

    json_str = response.strip
    json_str = json_str[/```(?:json)?\s*([\s\S]*?)```/, 1] || json_str if json_str.include?('```')
    JSON.parse(json_str.strip)
  rescue JSON::ParserError
    nil
  end

  def normalize_metadata(data)
    now = Date.current
    month = data['statement_month'].to_i.positive? ? data['statement_month'].to_i : now.month
    year = data['statement_year'].to_i.positive? ? data['statement_year'].to_i : now.year
    period_start, period_end = normalize_period(data, month: month, year: year)

    {
      bank_name: data['bank_name'].to_s.strip.presence || 'Unknown Bank',
      last_four: extract_last_four(data['account_last_four']),
      account_type: normalize_account_type(data['account_type']),
      month: month,
      year: year,
      period_start: period_start,
      period_end: period_end,
    }
  end

  # Returns [period_start, period_end] as Dates. Always returns a valid range:
  # if the extractor didn't surface one, fall back to the full month derived
  # from (month, year). Callers can later refine using actual transaction dates.
  def normalize_period(data, month:, year:)
    start_str = data['period_start'].to_s.strip
    end_str = data['period_end'].to_s.strip

    start_date = parse_iso_date(start_str)
    end_date = parse_iso_date(end_str)

    if start_date && end_date && end_date >= start_date
      return [start_date, end_date]
    end

    first = Date.new(year, month, 1)
    [first, first.end_of_month]
  rescue ArgumentError
    today = Date.current
    [today.beginning_of_month, today.end_of_month]
  end

  def parse_iso_date(str)
    return nil if str.blank?

    Date.iso8601(str)
  rescue ArgumentError, Date::Error
    nil
  end

  def extract_last_four(val)
    digits = val.to_s.gsub(/\D/, '')
    digits.length >= 4 ? digits[-4..] : digits.presence || '0000'
  end

  def normalize_account_type(val)
    v = val.to_s.downcase
    return 'credit_card' if v.include?('credit')
    return 'debit_card' if v.include?('debit')
    return 'savings' if v.include?('savings')
    return 'current' if v.include?('current')
    'credit_card' # default for card statements
  end

  def default_metadata
    now = Date.current
    {
      bank_name: 'Unknown Bank',
      last_four: '0000',
      account_type: 'credit_card',
      month: now.month,
      year: now.year,
      period_start: now.beginning_of_month,
      period_end: now.end_of_month,
    }
  end

  # Regex fallback when Ollama is unavailable (and an authoritative source
  # for fields like account_last_four that AI can't see in its truncated
  # view of large PDFs).
  def extract_with_regex
    return nil if @content.blank?

    bank          = extract_bank_regex
    last_four     = extract_last_four_regex
    account_type  = extract_account_type_regex
    month, year   = extract_period_regex
    period_start, period_end = extract_period_range_regex

    return nil if bank.blank? && last_four.blank?

    {
      'bank_name'         => bank.presence,
      'account_last_four' => last_four.presence,
      'account_type'      => account_type,
      'statement_month'   => month,
      'statement_year'    => year,
      'period_start'      => period_start&.iso8601,
      'period_end'        => period_end&.iso8601,
    }
  end

  # Canonical Indian-bank fingerprints. We scan the FULL document because
  # SBI prints "State Bank of India" only on page 2 of the relationship
  # summary, well past the header lines.
  BANK_FINGERPRINTS = [
    [/\bState\s+Bank\s+of\s+India\b/i,           'State Bank of India'],
    [/\bSBIN\d{7}\b/,                            'State Bank of India'], # IFSC prefix
    [/\bHDFC\s+Bank\b/i,                         'HDFC Bank'],
    [/\bHDFC\d{7}\b/,                            'HDFC Bank'],
    [/\bICICI\s+Bank\b/i,                        'ICICI Bank'],
    [/\bICIC\d{7}\b/,                            'ICICI Bank'],
    [/\bAxis\s+Bank\b/i,                         'Axis Bank'],
    [/\bUTIB\d{7}\b/,                            'Axis Bank'],
    [/\bKotak\s+Mahindra\b/i,                    'Kotak Mahindra Bank'],
    [/\bKKBK\d{7}\b/,                            'Kotak Mahindra Bank'],
    [/\bIndusInd\s+Bank\b/i,                     'IndusInd Bank'],
    [/\bYES\s+Bank\b/i,                          'YES Bank'],
    [/\bIDFC\s+(?:First\s+)?Bank\b/i,            'IDFC First Bank'],
    [/\bFederal\s+Bank\b/i,                      'Federal Bank'],
    [/\bPunjab\s+National\s+Bank\b/i,            'Punjab National Bank'],
    [/\bBank\s+of\s+Baroda\b/i,                  'Bank of Baroda'],
    [/\bCanara\s+Bank\b/i,                       'Canara Bank'],
    [/\bUnion\s+Bank\s+of\s+India\b/i,           'Union Bank of India'],
    [/\bRBL\s+Bank\b/i,                          'RBL Bank'],
    [/\bAmerican\s+Express\b/i,                  'American Express'],
  ].freeze

  def extract_bank_regex
    BANK_FINGERPRINTS.each do |re, name|
      return name if @content.match?(re)
    end

    header = @content.lines.first(10).join

    # Text before "Statement" / "Account Statement" (e.g. "Chase Bank Statement" -> "Chase Bank")
    m = header.match(/([A-Za-z0-9\s&.,'-]{3,60})\s+(?:Statement|Account Statement|Account Summary)/i)
    return clean_bank_name(m[1]) if m

    # "from [Bank Name]" or "Statement from [Bank Name]"
    m = header.match(/(?:Statement|Account)\s+from\s+([A-Za-z0-9\s&.,'-]{3,60})/i)
    return clean_bank_name(m[1]) if m

    # Line containing "Bank" or "Credit Union" - take that line
    line = @content.lines.find { |l| l =~ /\b(Bank|Credit Union|Financial)\b/i && l.strip.length.between?(3, 80) }
    return clean_bank_name(line.strip) if line

    nil
  end

  def clean_bank_name(str)
    str.to_s.strip.gsub(/\s+/, ' ').presence
  end

  # Pulls a labeled full account number anywhere in the document.
  # SBI prints "Account Number : 35035715556" on page 2; HDFC uses
  # "A/c No : 50100123456789"; ICICI uses "Account Number:". Numbers
  # shorter than 6 digits are filtered out so dates like "2026" don't
  # win.
  ACCOUNT_NUMBER_PATTERNS = [
    /Account\s+Number\s*[:\-]\s*(\d{6,20})/i,
    /A\/c\s+(?:No\.?|Number)\s*[:\-]\s*(\d{6,20})/i,
    /Account\s+No\.?\s*[:\-]\s*(\d{6,20})/i,
    /\bACCT\s+NO\.?\s*[:\-]\s*(\d{6,20})/i,
  ].freeze

  def extract_account_number_regex
    ACCOUNT_NUMBER_PATTERNS.each do |re|
      m = @content.match(re)
      return m[1] if m
    end
    nil
  end

  def extract_last_four_regex
    if (full = extract_account_number_regex)
      return full[-4..]
    end

    # Masked card numbers: ****1234, ••••1234, XXXX1234 — requires at
    # least 3 mask characters so we don't accidentally match a date.
    m = @content.match(/[X*•]{3,}\s*[X*•\d]*?(\d{4})\b/)
    return m[1] if m

    # Card-ending hint
    m = @content.match(/(?:ending(?:\s+in)?|last\s+4(?:\s+digits)?)\s*[:\-]?\s*(\d{4})/i)
    return m[1] if m

    nil
  end

  def extract_account_type_regex
    # Labeled "Product : Savings Account" wins (SBI / HDFC use this).
    m = @content.match(/Product\s*[:\-]\s*([A-Za-z][A-Za-z\s]{2,40})/i)
    if m
      label = m[1].downcase
      return 'savings'     if label.include?('saving')
      return 'current'     if label.include?('current')
      return 'credit_card' if label.include?('credit card')
      return 'debit_card'  if label.include?('debit card')
    end

    return 'savings'     if @content.match?(/\b(?:Savings\s+(?:Account|Bank)|SB\s+A\/c)\b/i)
    return 'current'     if @content.match?(/\b(?:Current\s+Account|CA\s+A\/c)\b/i)
    return 'credit_card' if @content.match?(/\b(?:Credit\s+Card\s+Statement|Card\s+Number)\b/i)
    return 'debit_card'  if @content.match?(/\bDebit\s+Card\b/i)

    nil
  end

  def extract_period_regex
    # Month names: "Jan 2024", "January 2024"
    m = @content.match(/(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{4})/i)
    if m
      month = Date::MONTHNAMES.index { |mth| mth&.start_with?(m[1].capitalize) }
      return [month, m[2].to_i]
    end

    # DD/MM/YYYY or MM/YYYY
    m = @content.match(/(\d{1,2})[\/\-](\d{4})/)
    return [m[1].to_i, m[2].to_i] if m

    [nil, nil]
  end

  # Tries to extract an explicit statement period range. Handles common forms:
  #   "Statement Period: 01/04/2024 to 31/03/2025"
  #   "From 01-Apr-2024 To 31-Mar-2025"
  #   "Period: 2024-04-01 - 2025-03-31"
  def extract_period_range_regex
    header = @content.lines.first(40).join

    m = header.match(/(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})\s*(?:to|-|–|—)\s*(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})/i)
    if m
      start_d = parse_dmy(m[1], m[2], m[3])
      end_d   = parse_dmy(m[4], m[5], m[6])
      return [start_d, end_d] if start_d && end_d && end_d >= start_d
    end

    m = header.match(/(\d{4})-(\d{1,2})-(\d{1,2})\s*(?:to|-|–|—)\s*(\d{4})-(\d{1,2})-(\d{1,2})/)
    if m
      start_d = safe_date(m[1], m[2], m[3])
      end_d   = safe_date(m[4], m[5], m[6])
      return [start_d, end_d] if start_d && end_d && end_d >= start_d
    end

    [nil, nil]
  end

  def parse_dmy(d, mo, y)
    year = y.to_i < 100 ? (y.to_i >= 50 ? 1900 + y.to_i : 2000 + y.to_i) : y.to_i
    safe_date(year, mo, d)
  end

  def safe_date(y, mo, d)
    Date.new(y.to_i, mo.to_i, d.to_i)
  rescue ArgumentError, Date::Error
    nil
  end
end
