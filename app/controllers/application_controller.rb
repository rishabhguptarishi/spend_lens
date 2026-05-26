class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  AI_PROVIDER_LABELS = {
    "gemini" => "Gemini",
    "openai" => "OpenAI",
    "ollama" => "Ollama",
  }.freeze

  inertia_share do
    provider = AiClient.provider
    {
      ai_provider: provider,
      ai_provider_label: AI_PROVIDER_LABELS[provider] || provider.to_s.capitalize,
    }
  end

  # Devise redirect after sign in
  def after_sign_in_path_for(_resource)
    dashboard_path
  end

  def after_sign_out_path_for(_resource)
    root_path
  end
end
