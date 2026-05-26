# frozen_string_literal: true

module Ai
  # Runs a bounded multi-step LLM + tools loop.
  #
  # Each step:
  #   1. Send current message history + tool declarations to the LLM.
  #   2. If the LLM returns a final answer, stop and return it.
  #   3. If it returns tool calls, execute them with the user's scoped tools,
  #      append observations to the history, and loop.
  #
  # Safety:
  #   - Max steps bound (default 6, override via AI_AGENTIC_MAX_STEPS).
  #   - Each tool result is truncated before being sent back.
  #   - Tool exceptions are returned to the LLM as observations, not raised.
  #   - Write tools only return signed proposal tokens; no mutations happen here.
  class AgenticChatService
    class AgenticDisabledError < StandardError; end

    MAX_STEPS_DEFAULT = 6
    MAX_OBSERVATION_BYTES = 8_000
    DEFAULT_TEMPERATURE = 0.2

    Result = Struct.new(:answer, :tool_trail, :proposals, :steps, :provider, :model, keyword_init: true)

    def initialize(user, mode: 'spending', financial_year: nil, allow_writes: true)
      @user = user
      @mode = mode.to_s == 'itr' ? 'itr' : 'spending'
      @financial_year = financial_year
      @allow_writes = allow_writes && @mode != 'itr'
    end

    def self.enabled?
      ENV.fetch('AI_AGENTIC_ENABLED', 'true').to_s.downcase != 'false' && AiClient.agentic_supported?
    end

    def run(question)
      raise AgenticDisabledError, "Agentic mode is disabled or the current AI_PROVIDER does not support tool calling." unless self.class.enabled?

      tools = Tools::Registry.for(mode: @mode, allow_writes: @allow_writes)
      declarations = Tools::Registry.declarations(tools)
      messages = build_initial_messages(question)
      tool_trail = []
      proposals = []
      final_answer = nil
      steps = 0

      max_steps.times do |i|
        steps = i + 1
        response = AiClient.chat_with_tools(messages, tools: declarations, temperature: DEFAULT_TEMPERATURE)
        calls = Array(response[:tool_calls])

        if calls.empty?
          final_answer = response[:text].presence || 'I could not generate a response.'
          break
        end

        messages << {
          role: 'assistant',
          content: response[:text],
          tool_calls: calls,
        }

        calls.each do |call|
          tool_class = Tools::Registry.find(tools, call[:name])
          observation, proposal = execute_tool(tool_class, call)
          tool_trail << { name: call[:name], args: call[:args], result_preview: preview(observation) }
          proposals << proposal if proposal

          messages << {
            role: 'tool',
            name: call[:name],
            tool_call_id: call[:id],
            content: truncate_observation(observation),
          }
        end
      end

      final_answer ||= 'I ran out of steps before reaching a final answer. Try a more focused question.'

      Result.new(
        answer: final_answer,
        tool_trail: tool_trail,
        proposals: proposals,
        steps: steps,
        provider: AiClient.provider,
        model: model_name
      )
    end

    private

    def max_steps
      ENV.fetch('AI_AGENTIC_MAX_STEPS', MAX_STEPS_DEFAULT).to_i.clamp(1, 12)
    end

    def model_name
      case AiClient.provider
      when 'gemini' then ENV.fetch('GEMINI_MODEL', 'gemini-1.5-flash')
      when 'openai' then ENV.fetch('OPENAI_MODEL', 'gpt-4o-mini')
      else AiClient.provider
      end
    end

    def build_initial_messages(question)
      [
        { role: 'system', content: system_prompt },
        { role: 'user', content: question.to_s },
      ]
    end

    def system_prompt
      base = <<~SYS
        You are Savvy, an Indian personal finance assistant for SpendLens.

        How to work:
        - You have tools to search transactions, summarise spend, compute budgets,
          look up cards, and read ITR/AIS data. Use them — never invent numbers.
        - Always call a tool before quoting specific amounts, merchants, or dates.
        - Use Indian Rupees (₹), round to the nearest rupee unless precision matters.
        - When the user asks for a change (recategorise, add budget, create rule),
          ALWAYS use a `propose_*` tool. NEVER claim a change is applied —
          the user has to click Apply on the returned proposal.
        - Be concise. Under 250 words unless asked for a list.
        - When unsure or data is missing, say so. Suggest what to upload.
        - This is assistive only; not tax or investment advice. Mention this for tax questions.

        Current context:
        - User id (internal): #{@user.id}
        - Mode: #{@mode}
        - Today: #{Date.current.iso8601}
      SYS

      base += "- ITR financial year start: #{@financial_year}\n" if @financial_year.present?
      base += itr_mode_rules if @mode == 'itr'
      base
    end

    # ITR-mode specific guardrails. The recurring failure mode is that the
    # model recommends ITR-2 with the reason "capital gains activity" and
    # then, on follow-up, admits it sees zero capital gains. The fix on
    # the data side is to only flag has_capital_gains_events when there's
    # a realization-side transaction; this prompt block prevents the model
    # from inventing a different justification.
    def itr_mode_rules
      <<~RULES

        ITR-mode rules:
        - ALWAYS call `itr_readiness` before recommending a form. Quote the
          `suggested_form.reason` verbatim — do not paraphrase it.
        - When the user asks "how do I save more tax?" / "what deductions
          should I claim?" / "what should I invest in to reduce tax?",
          call `tax_savings`. Read the returned `recommendations` and
          present the top 3-5 in plain language with the rupee figure
          ("save ~₹15,000 by topping up 80C").
        - Section 80C / 80D / 80CCD(1B) / 80E / 80G / 24b only apply under
          the OLD tax regime. Do not push them when
          `tax_savings.old_regime_relevant: false`.
        - Do NOT say "capital gains" / "capital gains activity" unless the
          tool returned `investment_summary.has_capital_gains_events: true`.
          Buys, SIPs, contributions and transfers-in are NOT capital gains
          events — they only deploy capital. Gains are realized on sell /
          transfer_out / maturity only.
        - If the user asks "what capital gains do you see?", look at
          `investment_summary.has_capital_gains_events` and `sells` total.
          If both are zero/false, say plainly that no realized gains were
          detected this FY and explain that buys/SIPs alone do not count.
        - Never contradict an earlier recommendation in the same session
          without telling the user what changed (e.g. "I miscited the
          reason — let me restate based on the data").
      RULES
    end

    def execute_tool(tool_class, call)
      return [{ error: "unknown tool: #{call[:name]}" }, nil] unless tool_class

      args = call[:args].is_a?(Hash) ? call[:args].with_indifferent_access : {}
      result = tool_class.new(@user).call(args.to_h.stringify_keys)
      proposal = result.is_a?(Hash) && tool_class.write_action? ? result[:proposal] : nil

      [result, proposal]
    rescue Tools::Base::ToolError => e
      [{ error: e.message }, nil]
    rescue => e
      Rails.logger.error "Agent tool #{call[:name]} crashed: #{e.class}: #{e.message}"
      [{ error: "tool failed: #{e.class}: #{e.message[0..200]}" }, nil]
    end

    def truncate_observation(obj)
      json = obj.to_json
      return obj if json.bytesize <= MAX_OBSERVATION_BYTES

      truncated = { truncated: true, note: "result exceeded #{MAX_OBSERVATION_BYTES} bytes", preview: json[0, MAX_OBSERVATION_BYTES] }
      truncated
    end

    def preview(obj)
      str = obj.is_a?(String) ? obj : obj.to_json
      str.to_s[0, 280]
    end
  end
end
