module Admin
  module Users
    class SessionsController < BaseController
      def destroy
        session_count = @user.revoke_sessions!
        audit_user("sessions_revoked", session_count: session_count.to_s)
        redirect_to admin_user_path(@user), notice: t("admin.sessions.revoked")
      end
    end
  end
end
