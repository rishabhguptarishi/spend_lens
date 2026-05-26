# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  def new
    render inertia: 'Auth/Login'
  end

  def create
    self.resource = warden.authenticate(auth_options)

    if resource
      sign_in(resource_name, resource)
      redirect_to after_sign_in_path_for(resource)
    else
      redirect_to new_user_session_path,
                  inertia: { errors: { base: 'Invalid email or password.' } }
    end
  end
end
