# frozen_string_literal: true

class InvestmentAccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_account, only: [:edit, :update, :destroy]

  def new
    render inertia: 'Investments/Accounts/New',
           props: { account_kinds: InvestmentAccount::ACCOUNT_KINDS }
  end

  def create
    @account = current_user.investment_accounts.build(account_params)
    if @account.save
      redirect_to investments_path, notice: 'Investment account created.'
    else
      render inertia: 'Investments/Accounts/New',
             props: { account_kinds: InvestmentAccount::ACCOUNT_KINDS, errors: @account.errors.to_hash }
    end
  end

  def edit
    render inertia: 'Investments/Accounts/Edit',
           props: { account: @account, account_kinds: InvestmentAccount::ACCOUNT_KINDS }
  end

  def update
    if @account.update(account_params)
      redirect_to investments_path, notice: 'Account updated.'
    else
      render inertia: 'Investments/Accounts/Edit',
             props: { account: @account, account_kinds: InvestmentAccount::ACCOUNT_KINDS, errors: @account.errors.to_hash }
    end
  end

  def destroy
    @account.destroy
    redirect_to investments_path, notice: 'Account deleted.'
  end

  private

  def set_account
    @account = current_user.investment_accounts.find(params[:id])
  end

  def account_params
    params.require(:investment_account).permit(:name, :provider, :account_kind, :notes)
  end
end
