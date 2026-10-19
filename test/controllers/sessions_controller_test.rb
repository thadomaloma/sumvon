require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "sign-in password field has a show-password toggle that starts hidden" do
    get new_session_path

    assert_select "[data-controller='password-visibility']" do
      assert_select "input#password[type=password][autocomplete='current-password'][data-password-visibility-target=input]"
      assert_select "button.password-toggle[type=button][hidden][aria-pressed=false][aria-controls=password][aria-label=?]", I18n.t("auth.show_password")
    end
  end

  test "new redirects an authenticated user home" do
    sign_in_as(@user)
    get new_session_path
    assert_redirected_to root_path
  end

  test "authenticated desktop navigation exposes settings and sign out" do
    sign_in_as(@user)

    get root_path

    assert_response :success
    assert_select "header details" do
      assert_select "a[href=?]", settings_path, text: I18n.t("nav.settings")
      assert_select "form[action=?] button", session_path, text: I18n.t("auth.sign_out")
    end
  end

  test "returns to a same-origin protected path after sign in" do
    get transactions_path(kind: "expense")
    assert_redirected_to new_session_path

    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to transactions_path(kind: "expense")
  end

  test "create with valid credentials" do
    assert_difference -> { AuditEvent.where(action: "auth.signed_in", subject_user: @user).count }, 1 do
      post session_path, params: { email_address: @user.email_address, password: "password" }
    end

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    assert_difference -> { AuditEvent.where(action: "auth.sign_in_failed", outcome: "failure").count }, 1 do
      post session_path, params: { email_address: @user.email_address, password: "wrong" }
    end

    assert_response :unprocessable_entity
    assert_nil cookies[:session_id]
  end

  test "a failed sign-in keeps the email, clears the password and shows the error inside the form" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_select "input#email_address[value=?]", @user.email_address
    assert_select "input#password:not([value])"
    assert_select "input#password[autofocus]"

    assert_select ".auth-pane #auth-alert[role=alert]", text: I18n.t("auth.invalid_credentials")
    assert_select "main > div[aria-live]", count: 0
    assert_select "input#email_address[aria-invalid=true][aria-describedby=auth-alert]"
    assert_select "input#password[aria-invalid=true][aria-describedby=auth-alert]"
  end

  test "expires an idle server-side session" do
    sign_in_as(@user)
    session_record = Current.session
    session_record.update_columns(updated_at: 15.days.ago)

    get root_path

    assert_redirected_to new_session_path
    assert_not Session.exists?(session_record.id)
    assert_empty cookies[:session_id]
  end

  test "expires a session at its absolute lifetime" do
    sign_in_as(@user)
    session_record = Current.session
    session_record.update_columns(created_at: 31.days.ago, updated_at: 1.hour.ago)

    get root_path

    assert_redirected_to new_session_path
    assert_not Session.exists?(session_record.id)
  end

  test "destroy" do
    sign_in_as(User.take)

    assert_difference -> { AuditEvent.where(action: "auth.signed_out").count }, 1 do
      delete session_path
    end

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]

    get root_path
    assert_redirected_to new_session_path
  end
end
