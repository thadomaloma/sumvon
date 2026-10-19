require "application_system_test_case"

class AuthenticationFlowTest < ApplicationSystemTestCase
  test "a user signs in and reaches the authenticated desktop app" do
    page.current_window.resize_to(1280, 900)
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_button "Sign in"

    assert_current_path root_path
    assert_text "Hello, One"
    assert_selector "header.app-header"
    assert_selector "nav[aria-label='Primary']"
  end

  test "the signed-in mobile shell and transaction filters fit the workflow" do
    page.current_window.resize_to(390, 844)
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_button "Sign in"

    assert_current_path root_path
    assert_selector "nav[aria-label='Mobile primary']"
    visit transactions_path
    assert_selector "details[data-filter-layout='mobile']"
    assert_selector "a[aria-label='Add transaction']"
  end
end
