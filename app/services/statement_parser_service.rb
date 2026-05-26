# frozen_string_literal: true

# Layered hybrid statement parser:
# 1. Extract text (pdf-reader → pdftotext -layout if needed)
# 2. Fingerprint the bank from the text (BankFingerprintRegistry)
# 3. Run the per-bank parser; fall through to the generic RegexExtractor
#    when no fingerprint matches
# 4. AI extraction in parallel; validate & merge (prefer regex on conflicts)
# 5. Balance-verify the parsed transactions (Phase 3 §4.5)
# 6. Persist with categorization, stamping parser metadata on the Statement
# 7. Portfolio extraction for fingerprints that opt into it
#    (:portfolio_extraction feature flag)
class StatementParserService
  GENERIC_PARSER_NAME    = StatementParsing::Banks::GenericParser.bank_name
  GENERIC_PARSER_VERSION = StatementParsing::Banks::GenericParser::VERSION

  def initialize(statement)
    @statement = statement
    @bank_account = statement.bank_account
    @user = @bank_account.user
  end

  def call
    return unless @statement.file.attached?

    file = @statement.file.download
    ext = @statement.file.filename.to_s.downcase.split('.').last
    format = ext == 'csv' ? :csv : :pdf

    # Layer 1: Text extraction
    text = StatementParsing::TextExtractor.extract(file, extension: ext)
    if text.blank?
      Rails.logger.warn 'Hybrid parser: no text extracted from file'
      @statement.update!(status: 'failed')
      return
    end

    # Layer 2: Fingerprint → per-bank parser → ParseResult
    parse_result = run_bank_parser(text: text, format: format)
    regex_txs = parse_result.transactions

    # Layer 3: AI extraction (parallel pathway)
    ai_input = StatementParsing::AiPreprocessor.prepare(
      format == :csv ? file.force_encoding('UTF-8') : text,
      format: format
    )
    ai_txs = AiStatementExtractorService.new(@statement).extract_transactions(ai_input)

    # Layer 4: Validate & merge
    trust_ai = StatementParsing::TransactionValidator.ai_batch_trustworthy?(ai_txs, regex_txs)
    merged = StatementParsing::TransactionMerger.merge(regex_txs, ai_txs, trust_ai: trust_ai)

    if merged.empty?
      Rails.logger.warn "Hybrid parser: no valid transactions (regex=#{regex_txs.size}, ai=#{ai_txs.size}, trust_ai=#{trust_ai})"
      @statement.update!(
        status: 'failed',
        parser_name: parse_result.parser_name,
        parser_version: parse_result.parser_version,
      )
      return
    end

    # Layer 5: Balance verification (golden rule)
    balance = StatementParsing::BalanceVerifier.verify(
      transactions: merged,
      opening_balance: parse_result.opening_balance,
      closing_balance: parse_result.closing_balance,
    )

    # Layer 6: Persist transactions + stamp parser metadata
    persister = StatementParsing::Persister.new(@statement, user: @user, bank_account: @bank_account)
    saved = persister.persist(merged)
    stamp_parser_metadata(parse_result: parse_result, balance: balance, ai_used: trust_ai)

    # Layer 7: Portfolio extraction — opt-in per fingerprint
    portfolio = run_portfolio_extraction(text: text, parse_result: parse_result)

    Rails.logger.info(
      "Hybrid parse complete: parser=#{parse_result.parser_name}@#{parse_result.parser_version} " \
      "regex=#{regex_txs.size} ai=#{ai_txs.size} merged=#{merged.size} saved=#{saved} " \
      "trust_ai=#{trust_ai} balance_verified=#{balance.verified.inspect} " \
      "delta=#{balance.delta.inspect} portfolio_holdings=" \
      "#{portfolio.holdings_created}+#{portfolio.holdings_updated} " \
      "portfolio_txns=#{portfolio.transactions_created}"
    )
  rescue => e
    Rails.logger.error "Hybrid parser failed: #{e.class}: #{e.message}"
    @statement.update!(status: 'failed')
  end

  private

  # Fingerprint the bank from the extracted text. If a parser is
  # registered, run it. Otherwise fall through to the legacy generic
  # RegexExtractor so we don't break uploads from un-fingerprinted
  # Tier-2/3 banks — they keep parsing exactly as before, just without
  # the per-bank version stamp and the bank-specific opening/closing
  # balance extraction.
  def run_bank_parser(text:, format:)
    if format == :pdf && (entry = StatementParsing::BankFingerprintRegistry.detect(text))
      Rails.logger.info "Fingerprint match: #{entry.name} -> #{entry.parser.name}@#{entry.parser::VERSION}"
      return entry.parser.new(content: text, format: format).call
    end

    Rails.logger.info "No fingerprint match — falling through to GenericParser"
    StatementParsing::Banks::GenericParser.new(content: text, format: format).call
  end

  def stamp_parser_metadata(parse_result:, balance:, ai_used:)
    @statement.update!(
      parser_name: parse_result.parser_name,
      parser_version: parse_result.parser_version,
      parse_quality: balance.to_h.merge(
        extraction_method: parse_result.extraction_method,
        ai_used: ai_used,
      ),
    )
  end

  # For ICICI consolidated statements the same PDF carries the FD / RD
  # passbook and the PPF account block alongside the spendable savings
  # ledger. Run PortfolioExtractor only when the fingerprint opts in
  # (avoids running a costly second pass over HDFC/Axis/SBI text).
  def run_portfolio_extraction(text:, parse_result:)
    entry = StatementParsing::BankFingerprintRegistry.lookup(parse_result.parser_name)
    opt_in = entry && Array(entry.features).include?(:portfolio_extraction)
    return null_portfolio_result unless opt_in

    StatementParsing::PortfolioExtractor
      .new(statement: @statement, content: text, user: @user)
      .call
  end

  def null_portfolio_result
    Struct.new(:holdings_created, :holdings_updated, :transactions_created)
      .new(0, 0, 0)
  end
end
