class BackupDatabaseJob < ApplicationJob
  queue_as :background

  def perform
    unless DatabaseBackup.configured?
      Rails.logger.warn("Skipping database backup: set #{DatabaseBackup::REQUIRED_ENV.join(', ')} to enable it.")
      return
    end

    key = DatabaseBackup.new.call
    Rails.logger.info("Database backup uploaded to R2 as #{key}")
  end
end
