module Auditing
  class Recorder
    ALLOWED_METADATA_KEYS = %w[
      admin_section changed_fields reason blocked_reason session_count
      deleted_user_id deleted_user_email_digest
    ].freeze

    class << self
      def record(action, actor: nil, subject: nil, source: "web", outcome: "success", request: nil, metadata: {})
        AuditEvent.create!(action:, actor_user: actor, subject_user: subject, source:, outcome:,
          request_id: request&.request_id&.to_s&.first(64), ip_digest: digest_ip(request&.remote_ip),
          metadata: sanitize(metadata))
      rescue ActiveRecord::ActiveRecordError => error
        Rails.error.report(error, context: { audit_action: action })
        nil
      end

      private
        def sanitize(metadata)
          metadata.to_h.stringify_keys.slice(*ALLOWED_METADATA_KEYS).compact
        end

        def digest_ip(ip)
          return if ip.blank?
          Digest::SHA256.hexdigest("#{Rails.application.secret_key_base}:#{ip}").first(32)
        end
    end
  end
end
