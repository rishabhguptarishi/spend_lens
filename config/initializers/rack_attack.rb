# frozen_string_literal: true

# Rate limiting for login and upload endpoints.
# See https://github.com/rack/rack-attack

Rack::Attack.enabled = !Rails.env.test?
Rack::Attack.cache.store = Rails.cache

Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env['rack.attack.match_data']
  now = match_data[:epoch_time]
  retry_after = (match_data[:period] - (now % match_data[:period])).to_s

  if request.get_header('HTTP_ACCEPT')&.include?('text/html')
    body = '<!DOCTYPE html><html><head><title>Too Many Requests</title></head><body><h1>Too many requests</h1><p>Please try again later.</p><p><a href="/">Go back</a></p></body></html>'
    [429, { 'Content-Type' => 'text/html', 'Retry-After' => retry_after }, [body]]
  else
    [429, { 'Content-Type' => 'application/json', 'Retry-After' => retry_after }, [{ error: 'Too many requests. Please try again later.' }.to_json]]
  end
end

# Throttle login attempts by IP (5 per minute)
Rack::Attack.throttle('logins/ip', limit: 5, period: 1.minute) do |req|
  req.ip if req.path == '/users/sign_in' && req.post?
end

# Throttle login attempts by email (5 per minute)
Rack::Attack.throttle('logins/email', limit: 5, period: 1.minute) do |req|
  if req.path == '/users/sign_in' && req.post?
    req.params.dig('user', 'email')&.to_s&.downcase&.presence
  end
end

# Throttle statement uploads (10 per minute per IP)
Rack::Attack.throttle('uploads/ip', limit: 10, period: 1.minute) do |req|
  req.ip if req.path == '/upload' && req.post?
end

# Throttle password reset (3 per hour per IP)
Rack::Attack.throttle('password_reset/ip', limit: 3, period: 1.hour) do |req|
  req.ip if req.path == '/users/password' && req.post?
end
