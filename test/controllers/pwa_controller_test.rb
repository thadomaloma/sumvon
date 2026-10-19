require "test_helper"

class PwaControllerTest < ActionDispatch::IntegrationTest
  test "manifest exposes install metadata without financial data" do
    get pwa_manifest_path

    assert_response :success
    assert_equal "application/manifest+json", response.media_type
    assert_match(/public/, response.headers["Cache-Control"])
    manifest = JSON.parse(response.body)
    assert_equal "Sumvon Personal Finance", manifest.fetch("name")
    assert_equal "Know where your money goes", manifest.fetch("description")
    assert_equal "standalone", manifest.fetch("display")
    assert_equal "/", manifest.fetch("start_url")
    assert_equal "#102b26", manifest.fetch("theme_color")
    assert_equal "#f7f3ea", manifest.fetch("background_color")
    assert_equal [ 192, 512, 192, 512 ], manifest.fetch("icons").map { |icon| icon.fetch("sizes").to_i }
    assert_no_match(/email_address|amount_minor|current_balance/i, response.body)
  end

  test "service worker is fresh and only declares safe static caching" do
    get pwa_service_worker_path

    assert_response :success
    assert_equal "application/javascript", response.media_type
    assert_match(/no-store/, response.headers["Cache-Control"])
    assert_equal "/", response.headers["Service-Worker-Allowed"]
    assert_match(/request\.method !== "GET"/, response.body)
    assert_match(/request\.mode === "navigate"/, response.body)
    assert_match(/cache: "no-store"/, response.body)
    assert_match(%r{/offline\.html}, response.body)
    assert_no_match(%r{/(transactions|accounts|budgets|reports)}, response.body)
  end

  test "authenticated html is private and disables turbo snapshot caching" do
    sign_in_as users(:one)
    get root_path

    assert_response :success
    assert_match(/private/, response.headers["Cache-Control"])
    assert_match(/no-store/, response.headers["Cache-Control"])
    assert_equal "no-cache", response.headers["Pragma"]
    assert_equal "camera=(self), microphone=(), geolocation=(), payment=()", response.headers["Permissions-Policy"]
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
    assert_select "meta[name='viewport'][content*='width=device-width']", count: 1
    assert_select "meta[name='viewport'][content*='user-scalable=no']", count: 0
    assert_select "script[type='importmap'][nonce]"
    assert_select "script[type='module'][nonce]"
    assert_match(/script-src 'self' 'nonce-/, response.headers.fetch("Content-Security-Policy"))
  end

  test "settings exposes native install help and a real service worker update action" do
    sign_in_as users(:one)

    get settings_path

    assert_response :success
    assert_select "details[data-pwa-target='installHelp'] summary", text: I18n.t("pwa.install_help")
    assert_select "button[data-action='pwa#checkForUpdate'][data-pwa-target='checkUpdateButton']", text: I18n.t("pwa.check_update")
    assert_select "[data-pwa-target='updateStatus'][aria-live='polite']"
  end

  test "offline fallback is public and explains the safety boundary" do
    get "/offline.html"

    assert_response :success
    assert_match(/offline/i, response.body)
    assert_match(/financial data/i, response.body)
  end
end
