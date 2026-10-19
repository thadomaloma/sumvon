module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[show edit update destroy]

    SAFE_FIELDS = %w[display_name country_code timezone default_currency].freeze

    def index
      scope = User.order(created_at: :desc)
      scope = filter_query(scope)
      scope = filter_suspended(scope)
      scope = filter_role(scope)
      @pagy, @users = pagy(scope, limit: 25)
      audit_admin_view("users")
    end

    def show
      load_user_summary
      audit_admin_view("user", subject: @user)
    end

    def edit
      audit_admin_view("user_edit", subject: @user)
    end

    def update
      @user.assign_attributes(user_params)
      changed_fields = @user.changed
      if @user.save
        Auditing::Recorder.record("admin.user_updated", actor: Current.user, subject: @user, request:,
          metadata: { admin_section: "users", changed_fields: changed_fields.sort })
        redirect_to admin_user_path(@user), notice: t("admin.edit.saved")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @user == Current.user
        Auditing::Recorder.record("admin.user_delete_blocked", actor: Current.user, subject: @user, request:,
          outcome: "blocked", metadata: { admin_section: "users", blocked_reason: "self" })
        redirect_to new_admin_user_deletion_path(@user), alert: t("admin.delete.self_blocked")
        return
      end

      if @user.last_active_admin?
        Auditing::Recorder.record("admin.user_delete_blocked", actor: Current.user, subject: @user, request:,
          outcome: "blocked", metadata: { admin_section: "users", blocked_reason: "last_admin" })
        redirect_to new_admin_user_deletion_path(@user), alert: t("admin.delete.last_admin")
        return
      end
      unless params[:confirmation_email].to_s.strip.casecmp?(@user.email_address)
        Auditing::Recorder.record("admin.user_delete_blocked", actor: Current.user, subject: @user, request:,
          outcome: "blocked", metadata: { admin_section: "users", blocked_reason: "confirmation_mismatch" })
        redirect_to new_admin_user_deletion_path(@user), alert: t("admin.delete.confirmation_mismatch")
        return
      end
      deleted_id = @user.id
      deleted_email_digest = Digest::SHA256.hexdigest(@user.email_address).first(16)
      @user.destroy!
      Auditing::Recorder.record("admin.user_deleted", actor: Current.user, subject: nil, request:,
        metadata: { admin_section: "users", deleted_user_id: deleted_id.to_s, deleted_user_email_digest: deleted_email_digest })
      redirect_to admin_users_path, notice: t("admin.delete.done")
    end

    private
      def set_user = @user = User.find(params[:id])

      def user_params
        params.require(:user).permit(*SAFE_FIELDS)
      end

      def filter_query(scope)
        query = params[:q].to_s.strip
        return scope if query.blank?

        escaped = ActiveRecord::Base.sanitize_sql_like(query)
        scope.where("users.display_name LIKE :query ESCAPE '\\' OR users.email_address LIKE :query ESCAPE '\\'", query: "%#{escaped}%")
      end

      def filter_suspended(scope)
        case params[:account_status]
        when "suspended" then scope.where.not(suspended_at: nil)
        when "active" then scope.where(suspended_at: nil)
        else scope
        end
      end

      def filter_role(scope)
        return scope unless params[:role] == "admin"

        admin_scope = scope.where(admin: true)
        admin_scope = admin_scope.or(scope.where(email_address: AdminAccess.emails)) if AdminAccess.emails.any?
        admin_scope
      end
  end
end
