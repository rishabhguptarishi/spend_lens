# frozen_string_literal: true

class BankAccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_bank_account, only: [:show, :edit, :update, :destroy]

  def index
    render inertia: 'BankAccounts/Index',
           props: {
             bank_accounts: current_user.bank_accounts.includes(:statements).as_json(include: :statements),
           }
  end

  def show
    statements = @bank_account.statements.order(year: :desc, month: :desc)
    render inertia: 'BankAccounts/Show',
           props: {
             bank_account: @bank_account.as_json(include: :statements),
             statements: statements.as_json,
           }
  end

  def new
    render inertia: 'BankAccounts/New'
  end

  def create
    @bank_account = current_user.bank_accounts.build(bank_account_params)
    if @bank_account.save
      redirect_to bank_accounts_path, notice: 'Bank account added successfully.'
    else
      render inertia: 'BankAccounts/New', props: { errors: @bank_account.errors.to_hash }
    end
  end

  def edit
    render inertia: 'BankAccounts/Edit', props: { bank_account: @bank_account }
  end

  def update
    if @bank_account.update(bank_account_params)
      redirect_to bank_account_path(@bank_account), notice: 'Bank account updated.'
    else
      render inertia: 'BankAccounts/Edit',
             props: { bank_account: @bank_account.as_json, errors: @bank_account.errors.to_hash }
    end
  end

  def destroy
    @bank_account.destroy
    redirect_to bank_accounts_path, notice: 'Bank account removed.'
  end

  private

  def set_bank_account
    @bank_account = current_user.bank_accounts.find(params[:id])
  end

  def bank_account_params
    params.require(:bank_account).permit(:name, :bank_name, :account_type, :last_four)
  end
end
