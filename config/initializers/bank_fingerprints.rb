# frozen_string_literal: true

# Bank fingerprint registration. Loaded once at boot.
#
# Per docs/INVESTMENT_ARCHITECTURE.html §4.2, each Tier-1 Indian bank we
# claim to support registers:
#
#   - ifsc_prefix     — for the IFSC-based fast path
#   - header_patterns — bank name / URL / unique column header regex,
#                        used when IFSC can't be sniffed from the text
#   - parser          — the per-bank parser class
#   - features        — capability flags read by StatementParserService
#                        (e.g. :portfolio_extraction triggers the
#                        PortfolioExtractor pass for ICICI consolidated)
#   - sample_path     — golden regression fixture (Phase 3 spec suite)
#
# To add a new bank: drop a file in app/services/statement_parsing/banks/,
# register it here, drop a sanitised text fixture in
# spec/fixtures/statements/, add an expected.yml, and let the regression
# spec runner pick it up.
Rails.application.config.to_prepare do
  StatementParsing::BankFingerprintRegistry.reset!

  StatementParsing::BankFingerprintRegistry.register(
    'HDFC Bank',
    ifsc_prefix: 'HDFC0',
    header_patterns: [/\bHDFC\s+BANK\b/i, /hdfcbank\.com/i],
    parser: StatementParsing::Banks::HdfcParser,
    features: [],
    sample_path: 'spec/fixtures/statements/hdfc_savings_sample.txt',
  )

  StatementParsing::BankFingerprintRegistry.register(
    'ICICI Bank',
    ifsc_prefix: 'ICIC0',
    header_patterns: [/\bICICI\s+Bank\b/i, /icicibank\.com/i],
    parser: StatementParsing::Banks::IciciParser,
    features: %i[multi_account_sections portfolio_extraction],
    sample_path: 'spec/fixtures/statements/icici_consolidated_sample.txt',
  )

  StatementParsing::BankFingerprintRegistry.register(
    'Axis Bank',
    ifsc_prefix: 'UTIB0',
    header_patterns: [/\bAxis\s+Bank\b/i, /\bStatement\s+of\s+Axis\b/i],
    parser: StatementParsing::Banks::AxisParser,
    features: [],
    sample_path: 'spec/fixtures/statements/axis_savings_sample.txt',
  )

  StatementParsing::BankFingerprintRegistry.register(
    'State Bank of India',
    ifsc_prefix: 'SBIN0',
    header_patterns: [/\bState\s+Bank\s+of\s+India\b/i, /\bonlinesbi\b/i],
    parser: StatementParsing::Banks::SbiParser,
    features: [],
    sample_path: 'spec/fixtures/statements/sbi_savings_sample.txt',
  )
end
