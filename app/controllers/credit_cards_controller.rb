# frozen_string_literal: true

class CreditCardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_credit_card, only: [:show, :edit, :update, :destroy, :fetch_rewards]

  def index
    render inertia: 'CreditCards/Index',
           props: { credit_cards: current_user.credit_cards.as_json }
  end

  def show
    render inertia: 'CreditCards/Show',
           props: { credit_card: @credit_card.as_json }
  end

  def new
    render inertia: 'CreditCards/New'
  end

  def create
    @credit_card = current_user.credit_cards.build(credit_card_params)
    if @credit_card.save
      redirect_to credit_cards_path, notice: 'Credit card added.'
    else
      render inertia: 'CreditCards/New', props: { errors: @credit_card.errors.to_hash }
    end
  end

  def edit
    render inertia: 'CreditCards/Edit', props: { credit_card: @credit_card.as_json }
  end

  def update
    if @credit_card.update(credit_card_params)
      redirect_to credit_card_path(@credit_card), notice: 'Credit card updated.'
    else
      render inertia: 'CreditCards/Edit',
             props: { credit_card: @credit_card.as_json, errors: @credit_card.errors.to_hash }
    end
  end

  def destroy
    @credit_card.destroy
    redirect_to credit_cards_path, notice: 'Credit card removed.'
  end

  def fetch_rewards
    rewards = CreditCardRewardsFetcherService.new(@credit_card).call
    if rewards
      @credit_card.update!(rewards_structure: rewards)
      redirect_to credit_card_path(@credit_card), notice: 'Rewards fetched from AI.'
    else
      redirect_to credit_card_path(@credit_card), alert: 'Could not fetch rewards. Check Ollama is running.'
    end
  end

  def suggestions
    ai_result = CreditCardRewardsSuggestorService.new(current_user).call
    portfolio = StatementCardRecommendationsService.new(current_user).call
    fee_analysis = CreditCardFeeAnalysisService.new(current_user).call

    render inertia: 'CreditCards/Suggestions',
           props: {
             suggestions: ai_result[:suggestions],
             summary: ai_result[:summary],
             spending_by_category: ai_result[:spending_by_category],
             message: ai_result[:message],
             portfolio_gaps: portfolio[:portfolio_gaps],
             high_spend_categories: portfolio[:high_spend_categories],
             fee_analysis: fee_analysis,
           }
  end

  def best_for
    result = BestCardForPurchaseService.new(current_user).call(
      category: params[:category],
      merchant: params[:merchant],
      amount: params[:amount]
    )
    render json: result
  end

  private

  def set_credit_card
    @credit_card = current_user.credit_cards.find(params[:id])
  end

  def credit_card_params
    params.require(:credit_card).permit(:name, :bank_name, :card_type, :annual_fee, :fee_waiver_spend, :notes)
  end
end
