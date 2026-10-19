module Admin
  module Users
    # The confirmation step before Admin::UsersController#destroy deletes an account.
    class DeletionsController < BaseController
      def new
        load_user_summary
        audit_user("user_delete_viewed")
      end
    end
  end
end
