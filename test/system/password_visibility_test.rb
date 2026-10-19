require "application_system_test_case"

class PasswordVisibilityTest < ApplicationSystemTestCase
  test "the sign-in password can be shown and hidden without losing what was typed" do
    visit new_session_path
    toggle = find("button[aria-label='#{I18n.t('auth.show_password')}']")
    field = find_field("Password")

    field.fill_in with: "secret12"
    toggle.click

    assert_equal "text", field[:type]
    assert_equal "secret12", field.value
    assert_selector "button.password-toggle[aria-pressed='true'][aria-label='#{I18n.t('auth.hide_password')}']"

    toggle.click

    assert_equal "password", field[:type]
    assert_selector "button.password-toggle[aria-pressed='false']"
  end

  test "signing in still works after revealing the password" do
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    find("button.password-toggle").click
    assert_equal "text", find_field("Password")[:type]

    click_button "Sign in"

    assert_current_path root_path
  end
end
