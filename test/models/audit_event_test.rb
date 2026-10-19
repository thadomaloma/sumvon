require "test_helper"

class AuditEventTest < ActiveSupport::TestCase
  test "recorder keeps only approved operational metadata and hashes the IP" do
    request = Struct.new(:request_id, :remote_ip).new("request-123", "203.0.113.42")

    event = Auditing::Recorder.record("admin.user_suspended", actor: users(:one), subject: users(:two),
      request:, metadata: { admin_section: "users", session_count: "2", amount_minor: 99_999,
        description: "private purchase", password: "never-store" })

    assert_equal({ "admin_section" => "users", "session_count" => "2" }, event.metadata)
    assert_equal 32, event.ip_digest.length
    assert_not_equal "203.0.113.42", event.ip_digest
    assert_equal "request-123", event.request_id
  end

  test "unknown actions and invalid sources are rejected" do
    event = AuditEvent.new(action: "financial.raw_dump", source: "browser", outcome: "success")

    assert_not event.valid?
    assert event.errors[:action].present?
    assert event.errors[:source].present?
  end
end
