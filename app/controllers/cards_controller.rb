# frozen_string_literal: true

class CardsController < ApplicationController
  before_action :authenticate_user!

  def index
    year = (params[:year] || Date.current.year).to_i
    month = params[:month]&.to_i

    range = if month
              Date.new(year, month).beginning_of_month..Date.new(year, month).end_of_month
            else
              Date.new(year).beginning_of_year..Date.new(year).end_of_year
            end

    bank_accounts = current_user.bank_accounts

    comparison = bank_accounts.map do |account|
      expenses = Transaction
        .joins(:statement)
        .where(statements: { bank_account_id: account.id })
        .where(transaction_type: 'debit')
        .where(date: range)
        .sum(:amount)

      income = Transaction
        .joins(:statement)
        .where(statements: { bank_account_id: account.id })
        .where(transaction_type: 'credit')
        .where(date: range)
        .sum(:amount)

      tx_count = Transaction
        .joins(:statement)
        .where(statements: { bank_account_id: account.id })
        .where(date: range)
        .count

      by_category = Transaction
        .joins(:statement)
        .joins('LEFT JOIN categories ON categories.id = transactions.category_id')
        .where(statements: { bank_account_id: account.id })
        .where(transaction_type: 'debit')
        .where(date: range)
        .group('COALESCE(categories.name, \'Uncategorized\')')
        .sum(:amount)

      {
        id: account.id,
        name: account.name,
        bank_name: account.bank_name,
        last_four: account.last_four,
        account_type: account.account_type,
        expenses: expenses.to_f,
        income: income.to_f,
        transactions_count: tx_count,
        by_category: by_category,
      }
    end

    render inertia: 'Cards/Index',
           props: {
             comparison: comparison,
             year: year,
             month: month,
           }
  end
end
