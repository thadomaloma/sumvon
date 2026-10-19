module Admin
  module Users
    class SuspensionsController < BaseController
      def create
        if @user == Current.user
          audit_user("user_suspension_blocked", outcome: "blocked", blocked_reason: "self")
          redirect_to admin_user_path(@user), alert: t("admin.suspension.self_blocked")
        elsif @user.last_active_admin?
          audit_user("user_suspension_blocked", outcome: "blocked", blocked_reason: "last_admin")
          redirect_to admin_user_path(@user), alert: t("admin.suspension.last_admin")
        else
          session_count = @user.suspend!
          audit_user("user_suspended", session_count: session_count.to_s)
          redirect_to admin_user_path(@user), notice: t("admin.suspension.suspended")
        end
      end

      def destroy
        @user.reactivate!
        audit_user("user_reactivated")
        redirect_to admin_user_path(@user), notice: t("admin.suspension.reactivated")
      end
    end
  end
end
