class AdminAccess
  class << self
    def allowed_email?(email)
      email.to_s.downcase.in?(emails)
    end

    def emails
      ENV.fetch("ADMIN_EMAILS", "").split(",").filter_map do |value|
        value.strip.downcase.presence
      end.freeze
    end

    # Counts distinct users who currently have admin access, whether granted through the
    # database `admin` flag, the ADMIN_EMAILS allowlist, or both. Used to block an admin
    # action that would leave Sumvon with zero effective super admins.
    def effective_admin_count
      scope = User.where(admin: true, suspended_at: nil)
      scope = scope.or(User.where(email_address: emails, suspended_at: nil)) if emails.any?
      scope.count
    end
  end
end
