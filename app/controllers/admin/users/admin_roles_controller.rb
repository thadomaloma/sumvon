module Admin
  module Users
    class AdminRolesController < BaseController
      def create
        @user.update!(admin: true)
        audit_user("role_granted")
        redirect_to admin_user_path(@user), notice: t("admin.role.granted")
      end

      def destroy
        if @user.env_admin?
          redirect_to admin_user_path(@user), alert: t("admin.role.env_protected")
        elsif @user.last_active_admin?
          audit_user("role_change_blocked", outcome: "blocked", blocked_reason: "last_admin")
          redirect_to admin_user_path(@user), alert: t("admin.role.last_admin")
        else
          @user.update!(admin: false)
          audit_user("role_revoked")
          redirect_to admin_user_path(@user), notice: t("admin.role.revoked")
        end
      end
    end
  end
end
