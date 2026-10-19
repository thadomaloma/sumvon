require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "new asks for one password with its requirement shown up front" do
    get new_registration_path

    assert_response :success
    assert_select "label[for=user_password]", text: /#{I18n.t("auth.create_password")}/
    assert_select "input#user_password[autocomplete='new-password'][minlength='8'][aria-describedby='password-hint']"
    assert_select "#password-hint", text: I18n.t("auth.password_hint")
    assert_select "input[name='user[password_confirmation]']", count: 0
    assert_select "a[href=?]", new_session_path, text: I18n.t("auth.sign_in_instead")
  end

  test "the required name, email and password fields are marked with a visual asterisk" do
    get new_registration_path

    { user_display_name: I18n.t("auth.your_name"), user_email_address: User.human_attribute_name(:email_address),
      user_password: I18n.t("auth.create_password") }.each do |id, label|
      assert_select "label[for=#{id}]", text: /#{Regexp.escape(label)}\s*\*/ do
        assert_select "span[aria-hidden=true]", text: "*"
      end
      assert_select "input##{id}[required]"
    end
  end

  test "time zone options carry their IANA names so the browser zone can be preselected" do
    get new_registration_path

    assert_select "details[data-controller='timezone-detect'] select#user_timezone option[value='Kolkata'][data-iana~='Asia/Kolkata']"
  end

  test "create signs up without a password confirmation" do
    assert_difference -> { User.count }, 1 do
      post registration_path, params: { user: { display_name: "New Person", email_address: "new.person@example.com", password: "long-enough-password",
        country_code: "IN", default_currency: "INR", timezone: "Kolkata" } }
    end

    assert_redirected_to new_financial_account_path
  end

  test "a short password is reported next to the field" do
    assert_no_difference -> { User.count } do
      post registration_path, params: { user: { display_name: "New Person", email_address: "short.password@example.com", password: "short",
        country_code: "IN", default_currency: "INR", timezone: "Kolkata" } }
    end

    assert_response :unprocessable_entity
    assert_select "input#user_password[aria-invalid=true][aria-describedby='password-hint user_password_error']"
    assert_select "#user_password_error.field-error", text: /too short/
    assert_select "input#user_email_address:not([aria-invalid])"
  end
end
