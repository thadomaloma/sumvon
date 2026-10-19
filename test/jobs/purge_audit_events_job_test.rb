require "test_helper"

class PurgeAuditEventsJobTest < ActiveJob::TestCase
  test "removes expired events but preserves the current audit trail" do
    old = AuditEvent.create!(action: "auth.sign_in_failed", outcome: "failure", created_at: 13.months.ago)
    recent = AuditEvent.create!(action: "auth.sign_in_failed", outcome: "failure", created_at: 2.days.ago)

    PurgeAuditEventsJob.perform_now

    assert_not AuditEvent.exists?(old.id)
    assert AuditEvent.exists?(recent.id)
  end
end
