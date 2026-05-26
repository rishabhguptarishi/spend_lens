# frozen_string_literal: true

# AI extraction from any tax doc registered in ItrDocumentRegistry.
#
# Each doc type ships its own minimal JSON schema in the registry. We
# build a tight prompt around that schema, ask the LLM for ONLY those
# fields, and store the parsed JSON in extracted_data.
#
# Type-specific parsers (broker P&L CSV, MF CG PDF, CDSL CAS PDF) still
# take precedence — they're faster, cheaper, and don't hallucinate. AI
# is the fallback when there's no deterministic parser for the type.
class TaxDocumentExtractorService
  def initialize(document)
    @document = document
  end

  def call
    return {} unless @document.file.attached?

    @document.update!(extraction_status: 'extracting')
    data = extract_for_document_type
    if data.blank?
      text = extract_text
      data = extract_with_ai(text) if text.present?
    end
    @document.update!(
      extracted_data: data,
      extraction_status: data.present? ? 'extracted' : 'failed'
    )
    data
  rescue => e
    Rails.logger.warn "Tax doc extract failed: #{e.message}"
    @document.update!(extraction_status: 'failed')
    {}
  end

  private

  def extract_for_document_type
    case @document.document_type
    when 'broker_pl'
      extract_broker_pl
    when 'mf_cg'
      extract_mf_cg
    else
      {}
    end
  end

  def extract_broker_pl
    content = @document.file.download
    filename = @document.file.filename.to_s.downcase

    if filename.end_with?('.csv')
      rows = InvestmentImports::BrokerCsvParser.parse(
        content.force_encoding('UTF-8'),
        source: 'zerodha',
        financial_year_start: @document.financial_year_start
      )
      return {} if rows.empty?

      sells = rows.select { |r| r[:kind] == 'sell' }
      {
        'transactions' => rows.map { |r| stringify_row(r) },
        'stcg' => sells.sum { |r| r[:amount].to_f },
        'ltcg' => 0,
        'parser' => 'broker_csv',
      }
    elsif filename.end_with?('.pdf')
      text = StatementParsing::TextExtractor.extract(content, extension: 'pdf')
      rows = InvestmentImports::BrokerCsvParser.parse(text, source: 'zerodha', financial_year_start: @document.financial_year_start) if text.present?
      return { 'transactions' => rows.map { |r| stringify_row(r) }, 'parser' => 'pdf_regex' } if rows.present? && rows.any?
    end

    {}
  end

  def extract_mf_cg
    content = @document.file.download
    filename = @document.file.filename.to_s.downcase
    fy = @document.financial_year_start

    text = if filename.end_with?('.pdf')
             StatementParsing::TextExtractor.extract(content, extension: 'pdf')
           else
             content.force_encoding('UTF-8')
           end

    rows = InvestmentImports::MfCasParser.parse(text, source: 'mf_cas', financial_year_start: fy)
    return {} if rows.empty?

    {
      'transactions' => rows.map { |r| stringify_row(r) },
      'stcg' => rows.select { |r| r[:kind] == 'sell' }.sum { |r| r[:amount].to_f },
      'parser' => 'mf_cas',
    }
  end

  def stringify_row(r)
    {
      'date' => r[:date].to_s,
      'kind' => r[:kind],
      'amount' => r[:amount],
      'description' => r[:description],
      'asset_class' => r[:asset_class],
      'symbol' => r[:symbol],
    }.compact
  end

  def extract_text
    content = @document.file.download
    ext = @document.file.filename.to_s.downcase

    if ext.end_with?('.json')
      return content.force_encoding('UTF-8')
    end

    if ext.end_with?('.pdf')
      return StatementParsing::TextExtractor.extract(content, extension: 'pdf')
    end

    content.force_encoding('UTF-8')
  end

  def extract_with_ai(text)
    return parse_json_upload(text) if @document.file.filename.to_s.downcase.end_with?('.json')

    return {} if text.blank?

    user = @document.user
    return {} unless user.user_preference.ai_enabled?

    prefs = user.user_preference
    schema_keys = ItrDocumentRegistry.ai_schema_for(@document.document_type)
    entry = ItrDocumentRegistry.find(@document.document_type)
    label = ItrTaxDocument.label_for(@document.document_type)

    return {} if schema_keys.blank?

    # Type-specific guidance keeps the prompt small but accurate. For
    # deduction proofs we hint at the section so the model doesn't
    # confuse, say, an ELSS receipt with an LIC premium.
    section_hint = entry&.deduction_section.present? ? " (Section #{entry.deduction_section})" : ''

    prompt = <<~PROMPT
      Extract structured tax data from this #{label}#{section_hint} document for Indian ITR.
      Return ONLY valid JSON. Use these EXACT keys (null when a field is missing):
      #{schema_keys.join(', ')}

      Rules:
      - All amounts are in INR. Strip the ₹ symbol and any commas. Return numbers, not strings.
      - Dates should be ISO 8601 (YYYY-MM-DD).
      - PANs are 10 characters: 5 letters + 4 digits + 1 letter.
      - Do NOT invent values. Use null when the document does not state a field.
      - If the document mentions multiple line items (TDS entries, transactions), return them as a JSON array under the appropriate key.

      Document text:
      #{text[0..10_000]}
    PROMPT

    content = AiClient.chat(prompt, prefs, format: "json")
    json_str = content[/\{[\s\S]*\}/] || content[/\[[\s\S]*\]/]
    return {} unless json_str

    data = JSON.parse(json_str)
    data.is_a?(Hash) ? data.stringify_keys : { "raw" => data }
  rescue JSON::ParserError
    {}
  end

  def parse_json_upload(text)
    data = JSON.parse(text)
    case @document.document_type
    when 'ais'
      normalize_ais(data)
    else
      data.is_a?(Hash) ? data.stringify_keys : { 'raw' => data }
    end
  rescue JSON::ParserError
    {}
  end

  def normalize_ais(data)
    {
      'salary' => dig_amount(data, 'salary', 'Salary'),
      'interest' => dig_amount(data, 'interest', 'Interest'),
      'dividends' => dig_amount(data, 'dividend'),
      'ltcg' => dig_amount(data, 'ltcg', 'LTCG'),
      'stcg' => dig_amount(data, 'stcg', 'STCG'),
      'tds' => dig_amount(data, 'tds', 'TDS'),
      'lines' => data['Part'] || data['parts'] || data['transactions'] || [],
    }
  end

  def dig_amount(data, *keys)
    keys.each do |k|
      v = data[k] || data[k.to_s] || data.dig('Part', k)
      return v.to_f if v.present?
    end
    0.0
  end
end
