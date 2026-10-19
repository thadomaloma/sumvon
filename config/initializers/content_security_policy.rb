Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.connect_src :self
    policy.font_src :self, :data
    policy.form_action :self
    policy.frame_ancestors :none
    policy.img_src :self, :data
    policy.manifest_src :self
    policy.object_src :none
    policy.script_src :self
    # Report and budget progress widths are deterministic server-rendered inline styles.
    policy.style_src :self, :unsafe_inline
    policy.worker_src :self
  end

  # Importmap emits inline import-map and module bootstrap tags. A per-request
  # nonce lets those trusted tags run without relaxing script-src for all inline scripts.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
