module Admin
  class DashboardController < BaseController
    def show
      @total_users = User.count
      @new_users = User.where(created_at: 30.days.ago..).count
      @recently_active_users = Session.where(updated_at: 7.days.ago..).distinct.count(:user_id)
      @suspended_users = User.where.not(suspended_at: nil).count
      @admin_count = AdminAccess.effective_admin_count
      @recent_users = User.order(created_at: :desc).limit(8)
      @transaction_count_30d = Transaction.where(created_at: 30.days.ago..).count
      @audit_events_today = AuditEvent.where(created_at: Time.current.beginning_of_day..).count
      @attention_events_7d = AuditEvent.where(created_at: 7.days.ago..).needing_attention.count
      @recent_audit_events = AuditEvent.excluding_views.includes(:actor_user, :subject_user).recent_first.limit(8)
      audit_admin_view("dashboard")
    end
  end
end
