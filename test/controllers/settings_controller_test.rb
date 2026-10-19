require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "settings exposes broad countries and the country currency mapping" do
    get settings_path

    assert_response :success
    assert_select "form[data-controller='country-currency'][data-country-currency-map-value]" do |forms|
      mapping = JSON.parse(forms.first["data-country-currency-map-value"])
      assert_equal "MMK", mapping.fetch("MM")
      assert_equal "BDT", mapping.fetch("BD")
    end
    assert_select "select[name='user[country_code]'] option[value='MM']", text: "Myanmar (MM)"
    assert_select "select[name='user[country_code]'] option[value='BD']", text: "Bangladesh (BD)"
    assert_select "select[name='user[default_currency]'] option[value='MMK']"
    assert_select "select[name='user[locale]']", count: 0
  end

  test "updates country and default currency without converting existing accounts" do
    account = @user.financial_accounts.create!(name: "Rupee account", account_type: :cash, currency: "INR")

    patch settings_path, params: { user: {
      display_name: @user.display_name, country_code: "MM", default_currency: "MMK",
      timezone: @user.timezone, locale: @user.locale
    } }

    assert_redirected_to settings_path
    assert_equal [ "MM", "MMK" ], @user.reload.values_at("country_code", "default_currency")
    assert_equal "INR", account.reload.currency
  end

  test "uses English for an account with the retired Mizo locale" do
    @user.update_column(:locale, "lus")

    get settings_path

    assert_response :success
    assert_select "html[lang='en']"
  end

  test "ignores submitted locale and normalizes a retired locale to English" do
    @user.update_column(:locale, "lus")

    patch settings_path, params: { user: {
      display_name: @user.display_name, country_code: @user.country_code,
      default_currency: @user.default_currency, timezone: @user.timezone, locale: "lus"
    } }

    assert_redirected_to settings_path
    assert_equal "en", @user.reload.locale
  end
end
