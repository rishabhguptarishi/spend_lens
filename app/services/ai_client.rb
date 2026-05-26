# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

class AiClient
  # Providers that support function/tool calling and are safe for agent loops.
  AGENTIC_PROVIDERS = %w[gemini openai].freeze

  # Main entrypoint to generate chat completions.
  def self.chat(prompt, user_preference = nil, format: nil, temperature: nil)
    provider = self.provider

    case provider
    when "gemini"
      chat_gemini(prompt, format: format, temperature: temperature)
    when "openai"
      chat_openai(prompt, format: format, temperature: temperature)
    else
      chat_ollama(prompt, user_preference, format: format, temperature: temperature)
    end
  end

  def self.provider
    ENV.fetch("AI_PROVIDER", "ollama").to_s.downcase
  end

  def self.agentic_supported?
    AGENTIC_PROVIDERS.include?(provider)
  end

  # Multi-turn chat-with-tools entrypoint used by the agent loop.
  # @param messages [Array<Hash>] role/content pairs (incl. tool results)
  # @param tools [Array<Hash>] function declarations (Gemini-style hash from Tool.declaration)
  # @return [Hash] { text: String|nil, tool_calls: [{ name:, args:, id: }], finish_reason: }
  def self.chat_with_tools(messages, tools:, temperature: 0.2)
    case provider
    when "gemini"
      chat_gemini_with_tools(messages, tools: tools, temperature: temperature)
    when "openai"
      chat_openai_with_tools(messages, tools: tools, temperature: temperature)
    else
      raise NotImplementedError, "Provider #{provider} does not support agentic tool calling. Set AI_PROVIDER=gemini or openai."
    end
  end

  private

  def self.chat_gemini(prompt, format: nil, temperature: nil)
    api_key = ENV["GEMINI_API_KEY"]
    if api_key.blank?
      raise "GEMINI_API_KEY is not configured in the environment. Please add it to your environment variables."
    end

    model = ENV.fetch("GEMINI_MODEL", "gemini-2.5-flash")
    url = URI("https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{api_key}")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.read_timeout = 60 # AI calls can take longer

    request = Net::HTTP::Post.new(url)
    request["Content-Type"] = "application/json"

    payload = {
      contents: [{
        parts: [{ text: prompt }]
      }]
    }

    generation_config = {}
    generation_config[:responseMimeType] = "application/json" if format == "json"
    generation_config[:temperature] = temperature if temperature.present?
    payload[:generationConfig] = generation_config if generation_config.any?

    request.body = payload.to_json
    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error "Gemini API Error: Status #{response.code} - #{response.body}"
      raise "Gemini API error: Status #{response.code} - #{response.body}"
    end

    data = JSON.parse(response.body)
    text = data.dig("candidates", 0, "content", "parts", 0, "text")
    text || ""
  end

  def self.chat_openai(prompt, format: nil, temperature: nil)
    api_key = ENV["OPENAI_API_KEY"]
    if api_key.blank?
      raise "OPENAI_API_KEY is not configured in the environment. Please add it to your environment variables."
    end

    model = ENV.fetch("OPENAI_MODEL", "gpt-4o-mini")
    endpoint = ENV.fetch("OPENAI_API_URL", "https://api.openai.com/v1/chat/completions")
    url = URI(endpoint)

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = url.scheme == "https"
    http.read_timeout = 60

    request = Net::HTTP::Post.new(url)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{api_key}"

    payload = {
      model: model,
      messages: [{ role: "user", content: prompt }]
    }

    payload[:response_format] = { type: "json_object" } if format == "json"
    payload[:temperature] = temperature if temperature.present?

    request.body = payload.to_json
    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error "OpenAI API Error: Status #{response.code} - #{response.body}"
      raise "OpenAI API error: Status #{response.code} - #{response.body}"
    end

    data = JSON.parse(response.body)
    text = data.dig("choices", 0, "message", "content")
    text || ""
  end

  def self.chat_ollama(prompt, user_preference, format: nil, temperature: nil)
    url = user_preference&.ollama_url.presence || ENV.fetch("OLLAMA_URL", "http://localhost:11434")
    model = user_preference&.ollama_model.presence || ENV.fetch("OLLAMA_MODEL", "llama3.2")

    client = Ollama.new(credentials: { address: url })

    options = {}
    options[:temperature] = temperature if temperature.present?

    params = {
      model: model,
      messages: [{ role: "user", content: prompt }],
      stream: false
    }
    params[:format] = "json" if format == "json"
    params[:options] = options if options.any?

    response = client.chat(params)
    result = response.is_a?(Array) ? response.last : response
    result.dig("message", "content") || ""
  end

  # ----------------------------------------------------------------------
  # Tool-calling implementations
  # ----------------------------------------------------------------------

  # Gemini expects:
  #   contents: [{ role: 'user'|'model'|'function', parts: [{ text }|{ functionCall }|{ functionResponse }] }]
  #   tools:    [{ function_declarations: [...] }]
  def self.chat_gemini_with_tools(messages, tools:, temperature: 0.2)
    api_key = ENV["GEMINI_API_KEY"]
    raise "GEMINI_API_KEY is not configured" if api_key.blank?

    model = ENV.fetch("GEMINI_MODEL", "gemini-2.5-flash")
    url = URI("https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{api_key}")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.read_timeout = 120

    payload = {
      contents: gemini_contents(messages),
      tools: [{ function_declarations: tools }],
      generationConfig: { temperature: temperature },
    }

    request = Net::HTTP::Post.new(url)
    request["Content-Type"] = "application/json"
    request.body = payload.to_json
    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error "Gemini tool-call API Error: #{response.code} - #{response.body}"
      raise "Gemini API error: #{response.code} - #{response.body}"
    end

    data = JSON.parse(response.body)
    parts = data.dig("candidates", 0, "content", "parts") || []
    finish_reason = data.dig("candidates", 0, "finishReason")

    tool_calls = parts.filter_map.with_index do |p, i|
      fc = p["functionCall"]
      next unless fc

      { id: "gemini_#{i}", name: fc["name"], args: fc["args"] || {} }
    end
    text = parts.filter_map { |p| p["text"] }.join("\n").presence

    { text: text, tool_calls: tool_calls, finish_reason: finish_reason, raw_parts: parts }
  end

  def self.gemini_contents(messages)
    messages.map do |m|
      case m[:role] || m["role"]
      when "user"
        { role: "user", parts: [{ text: m[:content].to_s }] }
      when "assistant"
        if m[:tool_calls].present?
          parts = m[:tool_calls].map { |tc| { functionCall: { name: tc[:name], args: tc[:args] || {} } } }
          parts.unshift(text: m[:content]) if m[:content].present?
          { role: "model", parts: parts }
        else
          { role: "model", parts: [{ text: m[:content].to_s }] }
        end
      when "tool"
        { role: "user", parts: [{
          functionResponse: {
            name: m[:name],
            response: { content: m[:content] }
          }
        }] }
      else
        { role: "user", parts: [{ text: m[:content].to_s }] }
      end
    end
  end

  # OpenAI tools API.
  def self.chat_openai_with_tools(messages, tools:, temperature: 0.2)
    api_key = ENV["OPENAI_API_KEY"]
    raise "OPENAI_API_KEY is not configured" if api_key.blank?

    model = ENV.fetch("OPENAI_MODEL", "gpt-4o-mini")
    endpoint = ENV.fetch("OPENAI_API_URL", "https://api.openai.com/v1/chat/completions")
    url = URI(endpoint)

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = url.scheme == "https"
    http.read_timeout = 120

    payload = {
      model: model,
      messages: openai_messages(messages),
      tools: tools.map { |t| { type: "function", function: t } },
      temperature: temperature,
    }

    request = Net::HTTP::Post.new(url)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{api_key}"
    request.body = payload.to_json
    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error "OpenAI tool-call API Error: #{response.code} - #{response.body}"
      raise "OpenAI API error: #{response.code} - #{response.body}"
    end

    data = JSON.parse(response.body)
    choice = data.dig("choices", 0) || {}
    msg = choice["message"] || {}
    text = msg["content"].presence
    tool_calls = Array(msg["tool_calls"]).map do |tc|
      args = parse_openai_args(tc.dig("function", "arguments"))
      { id: tc["id"], name: tc.dig("function", "name"), args: args }
    end

    { text: text, tool_calls: tool_calls, finish_reason: choice["finish_reason"] }
  end

  def self.openai_messages(messages)
    messages.map do |m|
      case m[:role] || m["role"]
      when "user"
        { role: "user", content: m[:content].to_s }
      when "system"
        { role: "system", content: m[:content].to_s }
      when "assistant"
        if m[:tool_calls].present?
          {
            role: "assistant",
            content: m[:content],
            tool_calls: m[:tool_calls].map do |tc|
              {
                id: tc[:id],
                type: "function",
                function: { name: tc[:name], arguments: (tc[:args] || {}).to_json }
              }
            end,
          }
        else
          { role: "assistant", content: m[:content].to_s }
        end
      when "tool"
        { role: "tool", tool_call_id: m[:tool_call_id], content: m[:content].is_a?(String) ? m[:content] : m[:content].to_json }
      else
        { role: "user", content: m[:content].to_s }
      end
    end
  end

  def self.parse_openai_args(raw)
    return {} if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end
end
