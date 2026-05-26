# frozen_string_literal: true

# Parent module for the bank-statement parsing pipeline.
#
# Concrete pieces (TextExtractor, RegexExtractor, AiPreprocessor,
# TransactionValidator, TransactionMerger, Persister, CreditKeywords) live in
# files under app/services/statement_parsing/ and are autoloaded by Zeitwerk.
#
# This file exists so Zeitwerk has a canonical definition file for the
# StatementParsing module itself, and so that module-level helpers like
# `.credit?` are reliably available without depending on submodule
# autoload order.
module StatementParsing
  # Convenience delegate used throughout the parsing pipeline.
  def self.credit?(description)
    CreditKeywords.match?(description)
  end
end
