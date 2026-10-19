require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "non-admin receives a private not found response" do
    sign_in_as users(:one)

    get admin_root_path

    assert_response :not_found
    assert AuditEvent.exists?(action: "admin.access_blocked", actor_user: users(:one), outcome: "blocked")

    get admin_users_path

    assert_response :not_found
  end

  test "admin can browse and filter the privacy-safe audit trail" do
    admin = users(:one)
    admin.update!(admin: true)
    sign_in_as admin
    Auditing::Recorder.record("auth.signed_in", actor: users(:two), subject: users(:two))
    Auditing::Recorder.record("admin.user_suspended", actor: admin, subject: users(:two),
      metadata: { admin_section: "users", session_count: "1" })

    get admin_audit_events_path, params: { action: "admin.user_suspended", outcome: "success", period: "7" }

    assert_response :success
    assert_select "h1", text: "Audit log"
    assert_match(/User suspended/i, response.body)
    assert_no_match(/Auth\.signed in/i, response.body)
    assert AuditEvent.exists?(action: "admin.audit_viewed", actor_user: admin)
  end

  test "user detail includes that user's audit history" do
    admin = users(:one)
    admin.update!(admin: true)
    sign_in_as admin
    Auditing::Recorder.record("password.changed", subject: users(:two))

    get admin_user_path(users(:two))

    assert_response :success
    assert_match(/Password changed/i, response.body)
  end

  test "admin dashboard shows operational metrics without any billing surface" do
    admin = users(:one)
    admin.update!(admin: true)
    sign_in_as admin
    users(:two).update!(suspended_at: Time.current)

    get admin_root_path

    assert_response :success
    assert_select "h1", text: "Admin dashboard"
    assert_select "nav.admin-tabs a[aria-current=page]", text: I18n.t("admin.nav.overview")
    assert_select "a[href=?]", admin_user_path(users(:two)), text: /Two User/ do
      assert_select ".status-badge", text: I18n.t("admin.suspended")
    end
    assert_no_match(/MRR|Sumvon Plus|subscription|Stripe/i, response.body)
  end

  test "admin can search and filter users by account and role status" do
    admin = users(:one)
    admin.update!(admin: true)
    sign_in_as admin
    users(:two).update!(suspended_at: Time.current)

    get admin_users_path, params: { q: "two@" }

    assert_response :success
    assert_select "h1", text: "Users"
    assert_select "td", text: /Two User/
    assert_select "td", text: /One User/, count: 0

    get admin_users_path, params: { account_status: "suspended" }
    assert_response :success
    assert_select "td", text: /Two User/
    assert_select "td", text: /One User/, count: 0

    get admin_users_path, params: { role: "admin" }
    assert_response :success
    assert_select "td", text: /One User/
    assert_select "td", text: /Two User/, count: 0

    get admin_user_path(users(:two))

    assert_response :success
    assert_select "h1", text: "Two User"
    assert_no_match(/subscription|billing/i, response.body)
  end

  test "an allowlisted owner email can open admin without a database role change" do
    original = ENV["ADMIN_EMAILS"]
    ENV["ADMIN_EMAILS"] = users(:one).email_address
    sign_in_as users(:one)

    get admin_root_path

    assert_response :success
  ensure
    ENV.delete("ADMIN_EMAILS")
    ENV["ADMIN_EMAILS"] = original if original
  end

  test "dashboard flags recent failed or blocked events and leaves page views out of recent activity" do
    admin = users(:one)
    admin.update!(admin: true)
    sign_in_as admin
    AuditEvent.create!(action: "auth.sign_in_failed", outcome: "failure", source: "web")
    AuditEvent.create!(action: "admin.users_viewed", outcome: "success", source: "web", actor_user: admin)

    get admin_root_path

    assert_select "[data-attention-callout]", text: /1 failed or blocked event/ do
      assert_select "a[href=?]", admin_audit_events_path(outcome: "attention", period: 7)
    end
    assert_select "#admin-recent-activity ~ ul, section[aria-labelledby=admin-recent-activity] ul" do
      assert_select "li", text: /Sign-in failed/
      assert_select "li", text: /Viewed user list/, count: 0
    end
  end

  test "dashboard shows an all-clear note when nothing failed or was blocked this week" do
    admin = users(:one)
    admin.update!(admin: true)
    sign_in_as admin

    get admin_root_path

    assert_select "[data-attention-callout]", count: 0
    assert_select ".admin-callout-ok", text: I18n.t("admin.all_clear")
  end
end
