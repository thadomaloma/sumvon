require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # One Chrome instance serves the whole run. Without these prefs its password manager
  # saves the first successful sign-in and autofills later sign-in pages, which races
  # with Capybara typing into the password field and makes tests flaky.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ] do |options|
    options.add_preference("credentials_enable_service", false)
    options.add_preference("profile.password_manager_enabled", false)
    options.add_preference("profile.password_manager_leak_detection", false)
  end
end
