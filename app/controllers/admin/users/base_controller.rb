module Admin
  module Users
    # Base for actions on a single user's account, nested under /admin/users/:user_id.
    class BaseController < Admin::BaseController
      before_action :set_user

      private
        def set_user = @user = User.find(params[:user_id])

        def audit_user(action, outcome: "success", **metadata)
          Auditing::Recorder.record("admin.#{action}", actor: Current.user, subject: @user, request:, outcome:,
            metadata: { admin_section: "users", **metadata })
        end
    end
  end
end
