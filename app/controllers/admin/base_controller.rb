module Admin
  class BaseController < ApplicationController
    before_action :require_admin_access

    private
      def require_admin_access
        return if Current.user.admin_access?

        Auditing::Recorder.record("admin.access_blocked", actor: Current.user, subject: Current.user,
          outcome: "blocked", request:, metadata: { admin_section: controller_name })
        head :not_found
      end

      def load_user_summary
        @account_count = @user.financial_accounts.count
        @transaction_count = @user.transactions.count
        @session_count = @user.sessions.count
        @last_active_at = @user.sessions.maximum(:updated_at)
        @audit_events = AuditEvent.where(actor_user: @user).or(AuditEvent.where(subject_user: @user))
          .includes(:actor_user, :subject_user).recent_first.limit(20)
      end

      def audit_admin_view(section, subject: nil)
        Auditing::Recorder.record("admin.#{section}_viewed", actor: Current.user, subject:, request:,
          metadata: { admin_section: section })
      end
  end
end
