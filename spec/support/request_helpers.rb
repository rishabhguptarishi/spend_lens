# frozen_string_literal: true

# Lightweight Devise sign-in helper for request specs.
# Posts to /users/sign_in with the user's credentials so the session cookie
# is set on the request agent.
module RequestHelpers
  def sign_in(user, password: "password123")
    post user_session_path, params: { user: { email: user.email, password: password } }
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
end
