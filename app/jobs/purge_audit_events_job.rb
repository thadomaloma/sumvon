class PurgeAuditEventsJob < ApplicationJob
  queue_as :background

  RETENTION_PERIOD = 1.year

  def perform
    AuditEvent.where(created_at: ...RETENTION_PERIOD.ago).in_batches(of: 1_000).delete_all
  end
end
