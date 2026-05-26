# frozen_string_literal: true

module StatementParsing
  # Layer 5: Save validated transactions with categorization.
  class Persister
    def initialize(statement, user:, bank_account:)
      @statement = statement
      @user = user
      @bank_account = bank_account
    end

    def persist(transactions)
      categorizer = TransactionCategorizationService.new(@user)
      created = 0

      transactions.each do |tx|
        next if duplicate?(tx)

        description = tx[:description]
        amount = tx[:amount]
        merchant = description.to_s[0..100]

        @statement.transactions.create!(
          date: tx[:date],
          description: description,
          amount: amount,
          transaction_type: tx[:transaction_type],
          merchant: merchant,
          category: categorizer.categorize(description, merchant: merchant),
          is_recurring: RecurringTransactionDetector.new(@user).recurring?(description, amount, tx[:date])
        )
        created += 1
      rescue => e
        Rails.logger.warn "Persist skip: #{e.message}"
      end

      refresh_period_from_transactions if created.positive?
      @statement.update!(status: created.positive? ? 'parsed' : 'failed')
      created
    end

    private

    # After saving, snap period_start/period_end to the actual min/max
    # transaction dates. The metadata extractor's range is a best-guess
    # before parsing; this makes the stored range an authoritative one
    # for overlap detection on the next upload.
    def refresh_period_from_transactions
      bounds = @statement.transactions.where.not(date: nil).pluck("MIN(date), MAX(date)").first
      return unless bounds && bounds[0].present?

      @statement.update_columns(period_start: bounds[0], period_end: bounds[1])
    end

    def duplicate?(tx)
      Transaction
        .joins(:statement)
        .where(statements: { bank_account_id: @bank_account.id })
        .exists?(date: tx[:date], amount: tx[:amount], description: tx[:description])
    end
  end
end
