require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes unsupported locales to English" do
    user = users(:one)
    user.locale = "lus"

    assert user.valid?
    assert_equal "en", user.locale
  end

  test "suspending ends every session" do
    user = users(:one)
    2.times { user.sessions.create! }

    assert_equal 2, user.suspend!
    assert user.reload.suspended?
    assert_empty user.sessions
  end

  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "requires a valid unique email and a strong-enough password" do
    duplicate = User.new(display_name: "Duplicate", email_address: " ONE@EXAMPLE.COM ", password: "short",
      password_confirmation: "short", country_code: "IN", timezone: "Kolkata", default_currency: "INR", locale: "en")

    assert_not duplicate.valid?
    assert duplicate.errors[:email_address].present?
    assert duplicate.errors[:password].present?

    duplicate.email_address = "not-an-email"
    duplicate.password = duplicate.password_confirmation = "long-enough-password"
    assert_not duplicate.valid?
    assert duplicate.errors[:email_address].present?
  end
end
