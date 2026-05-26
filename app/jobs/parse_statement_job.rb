# frozen_string_literal: true

class ParseStatementJob < ApplicationJob
  queue_as :default

  def perform(statement_id)
    statement = Statement.find_by(id: statement_id)
    return unless statement&.file&.attached?

    StatementParserService.new(statement).call

    user = statement.bank_account&.user
    if user&.user_preference&.auto_detect_investments?
      txn_ids = statement.transactions.pluck(:id)
      InvestmentDetectionService.new(user).scan_transactions!(transaction_ids: txn_ids)
    end
  rescue => e
    Rails.logger.error "ParseStatementJob #{statement_id}: #{e.message}"
    Statement.find_by(id: statement_id)&.update(status: 'failed')
    raise
  end
end
