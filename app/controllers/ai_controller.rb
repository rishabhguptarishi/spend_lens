# frozen_string_literal: true

class AiController < ApplicationController
  before_action :authenticate_user!

  def index
    categories = current_user.categories.pluck(:name).sort
    credit_cards = current_user.credit_cards.pluck(:name, :bank_name).map { |n, b| { name: n, bank: b } }

    render inertia: 'Ai/Index',
           props: {
             categories: categories,
             credit_cards: credit_cards,
             itr_years: FinancialYear.available_years,
             current_fy: FinancialYear.current_start_year,
             ai_provider: AiClient.provider,
             agentic_enabled: Ai::AgenticChatService.enabled? && current_user.user_preference.ai_agentic_enabled?,
             agentic_writes_enabled: current_user.user_preference.ai_agentic_writes?,
           }
  end

  def ask
    unless current_user.user_preference.ai_enabled?
      return render json: { error: 'AI assistant is disabled in Settings.' }, status: :forbidden
    end

    question = params[:question].to_s
    return render json: { error: 'Question is required' }, status: :unprocessable_entity if question.blank?

    if Ai::AgenticChatService.enabled? && agentic_mode_requested? && current_user.user_preference.ai_agentic_enabled?
      run_agentic(question)
    else
      run_single_shot(question)
    end
  rescue => e
    Rails.logger.error "AI Error: #{e.class}: #{e.message}"
    msg = "AI is unavailable: #{e.message}. Check AI_PROVIDER and API key configuration."
    render json: { error: msg, answer: nil }, status: :service_unavailable
  end

  def apply_proposal
    token = params[:token].to_s
    return render json: { error: 'token required' }, status: :unprocessable_entity if token.blank?

    result = Ai::ProposalExecutor.new(current_user).call(token)
    render json: { ok: true, result: result }
  rescue Ai::ProposalVerifier::InvalidProposalError => e
    render json: { error: e.message }, status: :unauthorized
  rescue Ai::ProposalExecutor::ExecutionError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue => e
    Rails.logger.error "Proposal apply failed: #{e.class}: #{e.message}"
    render json: { error: "Failed to apply: #{e.message}" }, status: :internal_server_error
  end

  private

  def agentic_mode_requested?
    return false if params[:agentic].to_s == 'false'

    true
  end

  def run_agentic(question)
    mode = params[:mode].to_s == 'itr' ? 'itr' : 'spending'
    allow_writes = current_user.user_preference.ai_agentic_writes?
    service = Ai::AgenticChatService.new(
      current_user,
      mode: mode,
      financial_year: params[:year],
      allow_writes: allow_writes
    )

    result = service.run(question)

    render json: {
      answer: result.answer,
      proposals: result.proposals,
      tool_trail: result.tool_trail,
      steps: result.steps,
      provider: result.provider,
      model: result.model,
      agentic: true,
    }
  rescue Ai::AgenticChatService::AgenticDisabledError => e
    Rails.logger.warn(e.message)
    run_single_shot(question)
  end

  def run_single_shot(question)
    summary = if params[:mode] == 'itr'
                AiItrContextService.new(
                  current_user,
                  financial_year_start: params[:year],
                  question: question
                ).call
              else
                AiTransactionContextService.new(current_user, question: question).call
              end

    response = ask_single_shot(question, summary, itr_mode: params[:mode] == 'itr')

    render json: {
      answer: response,
      proposals: [],
      tool_trail: [],
      provider: AiClient.provider,
      agentic: false,
    }
  end

  def ask_single_shot(question, context, itr_mode: false)
    role = itr_mode ? 'ITR and Indian tax prep assistant' : 'financial assistant for SpendLens (Indian personal finance)'
    prompt = <<~PROMPT
      You are Savvy, a helpful #{role}. The user tracks bank statements, investments, and tax documents.
      Be concise, actionable, and use Indian Rupees (₹). Round to nearest rupee.
      This is assistive only — not tax advice; remind user to verify with a CA when unsure.

      Context:
      #{context.to_json}

      User's question: #{question}

      Instructions:
      #{itr_mode ? itr_instructions : spending_instructions}
      - Keep responses under 300 words unless the user asks for a full list.
    PROMPT

    response = AiClient.chat(prompt, current_user.user_preference)
    response.presence || 'I could not generate a response.'
  end

  def spending_instructions
    <<~TXT
      - Answer based only on the data provided. If data is missing, say so politely.
      - The user can SEARCH transactions: use matching_transactions first, then recent_transactions.
      - For credit card questions, use credit_cards and best_card_by_top_categories.
    TXT
  end

  def itr_instructions
    <<~TXT
      - Help with ITR form choice, readiness checklist gaps, AIS reconciliation, regime comparison, capital gains, and tax-saving recommendations.
      - Reference suggested_form, reconciliation_gaps, regime_comparison, deductions, and tax_savings.top_recommendations from context.
      - When recommending a form, quote suggested_form.reason verbatim — do not paraphrase into "capital gains activity" or similar.
      - When asked "how do I save more tax?" or similar, use tax_savings.top_recommendations and cite specific actions + rupee figures.
      - Only mention "capital gains" if investment_summary.has_capital_gains_events is true. Buys / SIPs / contributions are NOT capital gains events — they only deploy capital. Gains are realized on sell / transfer_out / maturity.
      - 80C / 80D / 80CCD(1B) / 80E / 80G / 24b are OLD-regime only. Skip them if tax_savings.old_regime_relevant is false.
      - If has_capital_gains_events is false, plainly tell the user no realized gains were detected this FY and (if relevant) explain that buys / SIPs alone don't count.
      - Explain incometax.gov.in steps when asked about filing.
      - Do not guarantee tax outcomes or legal compliance.
    TXT
  end
end
