# frozen_string_literal: true

class StatementsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_bank_account
  before_action :set_statement, only: [:show, :destroy]

  def new
    render inertia: 'Statements/New',
           props: { bank_account: @bank_account }
  end

  def create
    @statement = @bank_account.statements.build(statement_params)
    @statement.month = params[:statement][:month].to_i
    @statement.year = params[:statement][:year].to_i
    if @statement.month.positive? && @statement.year.positive?
      first = Date.new(@statement.year, @statement.month, 1)
      @statement.period_start ||= first
      @statement.period_end ||= first.end_of_month
    end
    @statement.file.attach(params[:statement][:file]) if params[:statement][:file].present?

    if @statement.save
      if @statement.file.attached?
        @statement.update!(status: 'processing')
        ParseStatementJob.perform_later(@statement.id)
      end
      redirect_to bank_account_path(@bank_account), notice: 'Statement uploaded. Parsing in background.'
    else
      redirect_to new_bank_account_statement_path(@bank_account), inertia: { errors: @statement.errors }
    end
  end

  def show
    transactions = @statement.transactions.includes(:category).order(:date)
    render inertia: 'Statements/Show',
           props: {
             statement: @statement.as_json(include: :bank_account),
             transactions: transactions.as_json(include: :category),
             categories: current_user.categories,
           }
  end

  def destroy
    @statement.destroy
    redirect_to bank_account_path(@bank_account), notice: 'Statement deleted.'
  end

  private

  def set_bank_account
    @bank_account = current_user.bank_accounts.find(params[:bank_account_id])
  end

  def set_statement
    @statement = @bank_account.statements.find(params[:id])
  end

  def statement_params
    params.require(:statement).permit(:month, :year, :file)
  end
end
