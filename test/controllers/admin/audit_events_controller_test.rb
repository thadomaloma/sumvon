require "test_helper"

class Admin::AuditEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    sign_in_as @admin
    AuditEvent.delete_all
    AuditEvent.create!(action: "auth.signed_in", outcome: "success", source: "web", actor_user: users(:two), subject_user: users(:two))
    AuditEvent.create!(action: "auth.sign_in_failed", outcome: "failure", source: "web")
    AuditEvent.create!(action: "admin.role_change_blocked", outcome: "blocked", source: "web", actor_user: @admin, subject_user: users(:two))
    AuditEvent.create!(action: "admin.users_viewed", outcome: "success", source: "web", actor_user: @admin, created_at: 10.days.ago)
  end

  test "filters by event, which the old `action` param could never do" do
    get admin_audit_events_path, params: { event: "auth.sign_in_failed" }

    assert_response :success
    assert_select "[data-result-count]", text: "1 event"
    assert_select "table.audit-table tbody tr:not(.audit-day-row)", count: 1
    assert_select "table.audit-table", text: /Sign-in failed/
  end

  test "needs attention shows failed and blocked events together" do
    get admin_audit_events_path, params: { outcome: "attention" }

    assert_select "[data-result-count]", text: "2 events"
    assert_select "table.audit-table tr.is-attention", count: 2
  end

  test "can hide admin page views and limit the period" do
    get admin_audit_events_path, params: { hide_views: "1" }
    assert_select "table.audit-table", text: /Viewed user list/, count: 0

    get admin_audit_events_path, params: { period: "7" }
    assert_select "table.audit-table", text: /Viewed user list/, count: 0
    assert_select "table.audit-table", text: /Signed in/
  end

  test "lists everything by default with readable labels, self actions and a filter count only when filtering" do
    get admin_audit_events_path

    assert_select "nav.admin-tabs a[aria-current=page]", text: I18n.t("admin.nav.audit")
    assert_select "[data-result-count]", text: "4 events"
    assert_select "table.audit-table", text: /Two User · self/
    assert_select "table.audit-table", text: /Admin role change blocked/
    assert_select "details[data-filter-layout=mobile] .status-badge", count: 0
    assert_select "select[name=event] optgroup[label=?]", I18n.t("admin.audit.categories.auth")

    get admin_audit_events_path, params: { outcome: "failure" }
    assert_select "details[data-filter-layout=mobile] .status-badge", text: "1 active"
  end
end
