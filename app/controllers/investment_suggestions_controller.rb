# frozen_string_literal: true

class InvestmentSuggestionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_suggestion, only: %i[accept reject]

  def accept
    InvestmentSuggestionAcceptorService.new(current_user, @suggestion).call
    redirect_to investments_suggestions_path, notice: 'Added to portfolio.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to investments_suggestions_path, alert: e.record.errors.full_messages.join(', ')
  end

  def reject
    @suggestion.update!(status: 'rejected')
    redirect_to investments_suggestions_path, notice: 'Suggestion dismissed.'
  end

  def accept_all
    count = 0
    current_user.investment_suggestions
                .pending
                .includes(:source_transaction)
                .find_each do |s|
      InvestmentSuggestionAcceptorService.new(current_user, s).call
      count += 1
    rescue ActiveRecord::RecordInvalid
      next
    end
    redirect_to investments_path, notice: "Accepted #{count} suggestion(s)."
  end

  private

  def set_suggestion
    @suggestion = current_user.investment_suggestions.find(params[:id])
  end
end
