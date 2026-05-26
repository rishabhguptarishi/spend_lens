# frozen_string_literal: true

class TransactionsController < ApplicationController
  before_action :authenticate_user!

  def index
    scope = Transaction
      .joins(statement: :bank_account)
      .where(bank_accounts: { user_id: current_user.id })
      .includes(:category, statement: :bank_account)

    scope = scope.where('transactions.description ILIKE ?', "%#{params[:q]}%") if params[:q].present?
    scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?
    scope = scope.where(bank_accounts: { id: params[:bank_account_id] }) if params[:bank_account_id].present?
    scope = scope.where(transaction_type: params[:type]) if params[:type].present?
    scope = scope.where('transactions.date >= ?', params[:from]) if params[:from].present?
    scope = scope.where('transactions.date <= ?', params[:to]) if params[:to].present?
    scope = scope.where(is_recurring: true) if params[:recurring] == '1'

    transactions = scope.order(date: :desc).limit(500)

    render inertia: 'Transactions/Index',
           props: {
             transactions: transactions.as_json(include: { category: {}, statement: { include: :bank_account } }),
             categories: current_user.categories,
             bank_accounts: current_user.bank_accounts,
             filters: {
               q: params[:q],
               category_id: params[:category_id],
               bank_account_id: params[:bank_account_id],
               type: params[:type],
               from: params[:from],
               to: params[:to],
               recurring: params[:recurring],
             },
           }
  end

  def update
    transaction = current_user_transactions.find(params[:id])
    category_id = params[:transaction]&.dig(:category_id)

    if category_id.present?
      category = current_user.categories.find(category_id)
      transaction.update!(category: category)

      # Learn from correction
      TransactionCategorizationService.new(current_user).learn(
        transaction.description,
        merchant: transaction.merchant,
        category: category
      )
    end

    redirect_back fallback_location: transactions_path, notice: 'Category updated.'
  end

  def bulk_update
    ids = Array(params[:ids]).map(&:to_i).reject(&:zero?)
    category_id = params[:category_id]

    return redirect_back fallback_location: transactions_path, alert: 'Select transactions and a category.' if ids.blank? || category_id.blank?

    category = current_user.categories.find(category_id)
    transactions = current_user_transactions.where(id: ids)

    transactions.find_each do |tx|
      tx.update!(category: category)
      TransactionCategorizationService.new(current_user).learn(
        tx.description,
        merchant: tx.merchant,
        category: category
      )
    end

    redirect_back fallback_location: transactions_path, notice: "#{transactions.count} transactions updated."
  end

  private

  def current_user_transactions
    Transaction.joins(statement: :bank_account).where(bank_accounts: { user_id: current_user.id })
  end
end
