# frozen_string_literal: true

module Ai
  # Signs/verifies short-lived agent proposals so the LLM cannot trick the server
  # into applying actions the user did not see. The payload contains: { user_id,
  # kind, args, nonce, expires_at }.
  class ProposalVerifier
    EXPIRY = 1.hour
    PURPOSE = 'ai_proposal'
    ALLOWED_KINDS = %w[
      recategorize_transactions
      create_budget
      create_category_rule
      create_category
    ].freeze

    def self.sign(user, kind, args)
      raise ArgumentError, "unknown proposal kind: #{kind}" unless ALLOWED_KINDS.include?(kind.to_s)

      payload = {
        user_id: user.id,
        kind: kind.to_s,
        args: args || {},
        nonce: SecureRandom.hex(8),
        issued_at: Time.current.to_i,
      }
      verifier.generate(payload, purpose: PURPOSE, expires_in: EXPIRY)
    end

    def self.verify(token, user:)
      payload = verifier.verify(token, purpose: PURPOSE).with_indifferent_access
      raise InvalidProposalError, 'proposal does not belong to current user' if payload[:user_id].to_i != user.id
      raise InvalidProposalError, 'proposal kind not allowed' unless ALLOWED_KINDS.include?(payload[:kind])

      payload
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageEncryptor::InvalidMessage
      raise InvalidProposalError, 'proposal token invalid or expired'
    end

    def self.verifier
      Rails.application.message_verifier(:ai_proposal)
    end

    class InvalidProposalError < StandardError; end
  end
end
