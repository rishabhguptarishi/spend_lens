# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.font_src   :self, :https, :data
    policy.img_src    :self, :https, :data
    policy.object_src :none
    policy.script_src :self, :https
    policy.style_src  :self, :https
    policy.form_action :self
    policy.frame_ancestors :none
    policy.base_uri :self

    # Allow @vite/client to hot reload in development
    if Rails.env.development?
      # :unsafe_inline is required so the Bullet gem can inject its inline
      # <script> block (Bullet.alert / Bullet.console) before </body>.
      policy.script_src *policy.script_src, :unsafe_eval, :unsafe_inline, "http://#{ViteRuby.config.host_with_port}"
      policy.style_src *policy.style_src, :unsafe_inline, "http://#{ViteRuby.config.host_with_port}"
      policy.connect_src :self, "ws://#{ViteRuby.config.host_with_port}", "http://#{ViteRuby.config.host_with_port}"
    end

    # Vite may use blob: for worker scripts
    policy.script_src *policy.script_src, :blob if Rails.env.test?
  end

  # Report violations without enforcing (set to false to enforce)
  # config.content_security_policy_report_only = true
end
