# frozen_string_literal: true

InertiaRails.configure do |config|
  # Opt in to the Inertia 4.x behavior of always including an empty `errors`
  # hash so the frontend can rely on `props.errors` existing. Silences the
  # deprecation warning emitted by inertia_rails 3.x.
  config.always_include_errors_hash = true
end
