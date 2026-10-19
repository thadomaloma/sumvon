require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_password_path
    assert_response :success
    assert_select "h1", text: I18n.t("passwords.request.title")
    assert_select "form[action=?] input[type='email'][required]", passwords_path
    assert_select "a[href=?]", new_session_path, text: /#{I18n.t('passwords.back_to_sign_in')}/
    assert_match "Sumvon", response.body
  end

  test "create" do
    assert_difference -> { AuditEvent.where(action: "password.reset_requested", subject_user: @user).count }, 1 do
      post passwords_path, params: { email_address: @user.email_address }
    end
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "create for an unknown user redirects but sends no mail" do
    assert_no_difference -> { AuditEvent.where(action: "password.reset_requested").count } do
      post passwords_path, params: { email_address: "missing-user@example.com" }
    end
    assert_enqueued_emails 0
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
    assert_select "h1", text: I18n.t("passwords.reset.title")
    assert_select "input[name='password'][autocomplete='new-password'][aria-describedby='password-hint']"
    assert_select "#password-hint", text: I18n.t("auth.password_hint")
    assert_select "input[name='password_confirmation']", count: 0
  end

  test "edit with invalid password reset token" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_notice "reset link is invalid"
  end

  test "update" do
    assert_difference -> { AuditEvent.where(action: "password.changed", subject_user: @user).count }, 1 do
      assert_changes -> { @user.reload.password_digest } do
        put password_path(@user.password_reset_token), params: { password: "new-password" }
        assert_redirected_to new_session_path
      end
    end

    follow_redirect!
    assert_notice "Password has been reset"
  end

  test "update rejects a password shorter than eight characters" do
    token = @user.password_reset_token

    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "short" }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_select "#auth-alert[role=alert]", text: I18n.t("passwords.messages.mismatch")
  end

  private
    def assert_notice(text)
      assert_select "div", /#{text}/
    end
end
