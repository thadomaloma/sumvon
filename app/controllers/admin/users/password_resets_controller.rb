module Admin
  module Users
    class PasswordResetsController < BaseController
      def create
        PasswordsMailer.reset(@user).deliver_later
        audit_user("password_reset_initiated")
        redirect_to admin_user_path(@user), notice: t("admin.password_reset.sent")
      end
    end
  end
end
