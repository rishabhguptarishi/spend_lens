# frozen_string_literal: true

# Layered hybrid statement parser:
# 1. Extract text (pdf-reader → pdftotext -layout if needed)
# 2. Regex extraction + AI extraction (parallel)
# 3. Validate, merge (prefer regex on conflicts), dedupe
# 4. Persist with categorization
class StatementParserService
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

    # Layer 2: Regex + AI extraction
    regex_txs = StatementParsing::RegexExtractor.new(content: text, format: format).call

    ai_input = StatementParsing::AiPreprocessor.prepare(
      format == :csv ? file.force_encoding('UTF-8') : text,
      format: format
    )
    ai_txs = AiStatementExtractorService.new(@statement).extract_transactions(ai_input)

    # Layer 3–4: Validate & merge
    trust_ai = StatementParsing::TransactionValidator.ai_batch_trustworthy?(ai_txs, regex_txs)
    merged = StatementParsing::TransactionMerger.merge(regex_txs, ai_txs, trust_ai: trust_ai)

    if merged.empty?
      Rails.logger.warn "Hybrid parser: no valid transactions (regex=#{regex_txs.size}, ai=#{ai_txs.size}, trust_ai=#{trust_ai})"
      @statement.update!(status: 'failed')
      return
    end

    # Layer 5: Persist
    persister = StatementParsing::Persister.new(@statement, user: @user, bank_account: @bank_account)
    saved = persister.persist(merged)

    # Layer 6: Portfolio extraction (consolidated statements only).
    # For ICICI consolidated statements the same PDF carries the FD / RD
    # passbook and the PPF account block alongside the spendable savings
    # ledger. Surfacing those as holdings is no-op for HDFC/Axis/SBI but
    # restores ~₹3.83L of PPF + ₹3.38L of FDs to the user's net-worth view
    # in one shot for ICICI uploads.
    portfolio = StatementParsing::PortfolioExtractor
      .new(statement: @statement, content: text, user: @user)
      .call

    Rails.logger.info(
      "Hybrid parse complete: regex=#{regex_txs.size} ai=#{ai_txs.size} " \
      "merged=#{merged.size} saved=#{saved} trust_ai=#{trust_ai} " \
      "portfolio_holdings=#{portfolio.holdings_created}+#{portfolio.holdings_updated} " \
      "portfolio_txns=#{portfolio.transactions_created}"
    )
  rescue => e
    Rails.logger.error "Hybrid parser failed: #{e.class}: #{e.message}"
    @statement.update!(status: 'failed')
  end
end
