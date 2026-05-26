# frozen_string_literal: true

class DigestMailer < ApplicationMailer
  def monthly_digest(user)
    @user = user
    now = Date.current
    last_month = now - 1.month
    range = last_month.beginning_of_month..last_month.end_of_month

    tx = Transaction
      .joins(statement: :bank_account)
      .where(bank_accounts: { user_id: user.id })
      .where(date: range)

    @expenses = tx.where(transaction_type: 'debit').sum(:amount).to_f
    @income = tx.where(transaction_type: 'credit').sum(:amount).to_f
    @top_categories = tx
      .where(transaction_type: 'debit')
      .joins('LEFT JOIN categories ON categories.id = transactions.category_id')
      .group('COALESCE(categories.name, \'Uncategorized\')')
      .sum(:amount)
      .sort_by { |_, v| -v }
      .first(5)

    mail(
      to: user.email,
      subject: "Monthly digest: #{last_month.strftime('%B %Y')}",
    )
  end
end
