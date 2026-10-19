require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    @target = users(:two)
    sign_in_as @admin
  end

  test "the admin nav link is shown only to users with admin access" do
    get root_path
    assert_response :success
    assert_select "a[href=?]", admin_root_path

    sign_in_as @target
    get root_path
    assert_response :success
    assert_select "a[href=?]", admin_root_path, count: 0
  end

  test "a normal user receives a private not found response from every new admin route" do
    sign_in_as @target

    get edit_admin_user_path(@admin)
    assert_response :not_found
    get new_admin_user_deletion_path(@admin)
    assert_response :not_found

    assert_no_difference("User.count") do
      patch admin_user_path(@admin), params: { user: { display_name: "Hijacked" } }
    end
    assert_response :not_found
    assert_not_equal "Hijacked", @admin.reload.display_name

    post admin_user_admin_role_path(@target)
    assert_response :not_found
    assert_not @target.reload.admin?

    delete admin_user_admin_role_path(@admin)
    assert_response :not_found
    assert @admin.reload.admin?

    post admin_user_suspension_path(@admin)
    assert_response :not_found
    assert_not @admin.reload.suspended?

    delete admin_user_suspension_path(@admin)
    assert_response :not_found

    @admin.sessions.create!
    delete admin_user_sessions_path(@admin)
    assert_response :not_found
    assert @admin.sessions.exists?

    post admin_user_password_reset_path(@admin)
    assert_response :not_found

    assert_no_difference("User.count") do
      delete admin_user_path(@admin), params: { confirmation_email: @admin.email_address }
    end
    assert_response :not_found
  end

  test "suspended filter narrows the users index" do
    @target.update!(suspended_at: Time.current)

    get admin_users_path, params: { account_status: "suspended" }
    assert_response :success
    assert_select "td", text: /Two User/
    assert_select "td", text: /One User/, count: 0
  end

  test "show page renders every panel without error, including the suspended state" do
    @target.update!(suspended_at: Time.current)

    get admin_user_path(@target)

    assert_response :success
    assert_select "h1", text: @target.display_name
    assert_match(/#{Regexp.escape(I18n.t("admin.suspended"))}/, response.body)

    get new_admin_user_deletion_path(@target)
    assert_response :success
  end

  test "show page renders for an environment-allowlisted admin without a database role" do
    original = ENV["ADMIN_EMAILS"]
    ENV["ADMIN_EMAILS"] = @target.email_address

    get admin_user_path(@target)

    assert_response :success
    assert_match(/environment allowlist/i, response.body)
  ensure
    ENV.delete("ADMIN_EMAILS")
    ENV["ADMIN_EMAILS"] = original if original
  end

  test "admin edits safe profile fields and it is audited" do
    get edit_admin_user_path(@target)
    assert_response :success
    assert_select "h1", text: @target.display_name
    assert_match(/Edit profile/, response.body)

    patch admin_user_path(@target), params: { user: { display_name: "Updated Name", country_code: "JP",
      timezone: "Tokyo", default_currency: "JPY" } }

    assert_redirected_to admin_user_path(@target)
    assert_equal "Updated Name", @target.reload.display_name
    event = AuditEvent.find_by(action: "admin.user_updated", subject_user: @target)
    assert event.present?
    assert_includes event.metadata["changed_fields"], "display_name"
  end

  test "admin cannot mass-assign admin or password through the edit endpoint" do
    original_digest = @target.password_digest
    patch admin_user_path(@target), params: { user: { display_name: "Still Safe", admin: true,
      password: "hijacked123", password_digest: "x" } }

    assert_redirected_to admin_user_path(@target)
    assert_not @target.reload.admin?
    assert_equal original_digest, @target.password_digest
  end

  test "admin grants and revokes database admin role" do
    post admin_user_admin_role_path(@target)
    assert_redirected_to admin_user_path(@target)
    assert @target.reload.admin?
    assert AuditEvent.exists?(action: "admin.role_granted", subject_user: @target)

    delete admin_user_admin_role_path(@target)
    assert_redirected_to admin_user_path(@target)
    assert_not @target.reload.admin?
    assert AuditEvent.exists?(action: "admin.role_revoked", subject_user: @target)
  end

  test "last remaining effective super admin cannot be revoked" do
    other_admins = User.where(admin: true).where.not(id: @admin.id)
    other_admins.update_all(admin: false)
    assert_equal 1, AdminAccess.effective_admin_count

    delete admin_user_admin_role_path(@admin)

    assert_redirected_to admin_user_path(@admin)
    assert @admin.reload.admin?
    assert AuditEvent.exists?(action: "admin.role_change_blocked", subject_user: @admin, outcome: "blocked")
  end

  test "environment-allowlisted admin cannot be revoked through the database control" do
    original = ENV["ADMIN_EMAILS"]
    ENV["ADMIN_EMAILS"] = @target.email_address
    @target.update!(admin: true)

    delete admin_user_admin_role_path(@target)

    assert_redirected_to admin_user_path(@target)
    assert @target.reload.admin_access?
    assert_match(/environment allowlist/i, flash[:alert])
  ensure
    ENV.delete("ADMIN_EMAILS")
    ENV["ADMIN_EMAILS"] = original if original
  end

  test "admin suspends a user, revoking sessions and blocking sign-in" do
    @target.sessions.create!
    assert_equal 1, @target.sessions.count

    post admin_user_suspension_path(@target)

    assert_redirected_to admin_user_path(@target)
    assert @target.reload.suspended?
    assert_equal 0, @target.sessions.count
    assert AuditEvent.exists?(action: "admin.user_suspended", subject_user: @target)

    post session_path, params: { email_address: @target.email_address, password: "password" }
    assert_redirected_to new_session_path
    assert_equal 0, @target.sessions.count
    assert AuditEvent.exists?(action: "auth.sign_in_failed", subject_user: @target, outcome: "blocked")

    delete admin_user_suspension_path(@target)
    assert_not @target.reload.suspended?
    assert AuditEvent.exists?(action: "admin.user_reactivated", subject_user: @target)
  end

  test "suspending invalidates an already-signed-in session immediately" do
    sign_in_as @target
    get root_path
    assert_response :success

    @target.update!(suspended_at: Time.current)

    get root_path
    assert_redirected_to new_session_path
    assert_equal 0, @target.sessions.count
  end

  test "admin revokes sessions without suspending the account" do
    @target.sessions.create!
    @target.sessions.create!

    delete admin_user_sessions_path(@target)

    assert_redirected_to admin_user_path(@target)
    assert_equal 0, @target.sessions.count
    assert_not @target.reload.suspended?
    assert AuditEvent.exists?(action: "admin.sessions_revoked", subject_user: @target)
  end

  test "admin sends a password reset email instead of viewing the password" do
    post admin_user_password_reset_path(@target)

    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @target ]
    assert_redirected_to admin_user_path(@target)
    assert AuditEvent.exists?(action: "admin.password_reset_initiated", subject_user: @target)
  end

  test "delete confirmation screen requires exact email match" do
    get new_admin_user_deletion_path(@target)
    assert_response :success
    assert_select "h1", text: "Delete user"

    assert_no_difference("User.count") do
      delete admin_user_path(@target), params: { confirmation_email: "wrong@example.com" }
    end
    assert_redirected_to new_admin_user_deletion_path(@target)
    assert AuditEvent.exists?(action: "admin.user_delete_blocked", subject_user: @target, outcome: "blocked")
  end

  test "admin permanently deletes a user with correct confirmation and an audit trail" do
    account = @target.financial_accounts.create!(name: "Doomed", account_type: :bank, currency: "JPY")
    @target.transactions.create!(financial_account: account, category: Category.create!(name: "Doomed cat", kind: :expense),
      kind: :expense, amount_minor: 100, currency: "JPY", transaction_date: Date.current)
    target_id = @target.id

    assert_difference("User.count", -1) do
      delete admin_user_path(@target), params: { confirmation_email: @target.email_address }
    end

    assert_redirected_to admin_users_path
    assert_not User.exists?(target_id)
    assert_not FinancialAccount.exists?(account.id)
    event = AuditEvent.find_by(action: "admin.user_deleted")
    assert event.present?
    assert_nil event.subject_user_id
    assert_equal target_id.to_s, event.metadata["deleted_user_id"]
  end

  test "admin cannot delete their own active account" do
    assert_no_difference("User.count") do
      delete admin_user_path(@admin), params: { confirmation_email: @admin.email_address }
    end

    assert_redirected_to new_admin_user_deletion_path(@admin)
    assert AuditEvent.exists?(action: "admin.user_delete_blocked", subject_user: @admin, outcome: "blocked")
  end

  test "deleting one of several admins is allowed, leaving at least one effective admin" do
    other = User.create!(email_address: "second-admin@example.com", password: "password123",
      display_name: "Second Admin", country_code: "IN", timezone: "Kolkata", default_currency: "INR", admin: true)
    assert_equal 2, AdminAccess.effective_admin_count

    assert_difference("User.count", -1) do
      delete admin_user_path(other), params: { confirmation_email: other.email_address }
    end

    assert_equal 1, AdminAccess.effective_admin_count
  end

  test "an administrator cannot suspend their own active session" do
    assert_no_changes -> { @admin.reload.suspended_at } do
      post admin_user_suspension_path(@admin)
    end

    assert_redirected_to admin_user_path(@admin)
    assert AuditEvent.exists?(action: "admin.user_suspension_blocked", subject_user: @admin, outcome: "blocked")
  end

  test "the last active super admin cannot be suspended" do
    @target.update!(admin: true, suspended_at: Time.current)
    assert_equal 1, AdminAccess.effective_admin_count

    other_admin = User.create!(email_address: "acting-admin@example.com", password: "password123",
      display_name: "Acting Admin", country_code: "IN", timezone: "Kolkata", default_currency: "INR", admin: true)
    sign_in_as other_admin
    @admin.update!(admin: true)
    other_admin.update!(suspended_at: Time.current)
    sign_in_as @admin

    assert_equal 1, AdminAccess.effective_admin_count
    post admin_user_suspension_path(@admin)

    assert_not @admin.reload.suspended?
    assert AuditEvent.exists?(action: "admin.user_suspension_blocked", subject_user: @admin, outcome: "blocked")
  end
end
