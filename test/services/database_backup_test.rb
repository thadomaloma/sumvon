require "test_helper"
require "aws-sdk-s3"

class DatabaseBackupTest < ActiveSupport::TestCase
  # VACUUM INTO cannot run inside the transaction that wraps each test.
  self.use_transactional_tests = false

  test "uploads a gzipped, readable snapshot of the primary database" do
    uploaded = nil
    client = Aws::S3::Client.new(stub_responses: true)
    client.stub_responses(:put_object, ->(context) {
      uploaded = context.params.except(:body).merge(body: context.params[:body].read)
      {}
    })

    key = DatabaseBackup.new(client:, bucket: "example-backups", now: Time.utc(2026, 10, 19, 4, 10)).call

    assert_equal "sqlite/test/primary-20261019T041000Z.sqlite3.gz", key
    assert_equal({ bucket: "example-backups", key:, content_type: "application/gzip" }, uploaded.slice(:bucket, :key, :content_type))

    Dir.mktmpdir do |dir|
      restored = File.join(dir, "restored.sqlite3")
      File.binwrite(restored, Zlib.gunzip(uploaded[:body]))
      SQLite3::Database.new(restored, readonly: true) do |db|
        assert_equal "ok", db.get_first_value("PRAGMA integrity_check")
        assert_equal User.count, db.get_first_value("SELECT COUNT(*) FROM users")
      end
    end
  end

  test "the job skips quietly until R2 is configured" do
    DatabaseBackup::REQUIRED_ENV.each { |name| assert_nil ENV[name], "#{name} must be unset in tests" }

    assert_nothing_raised { BackupDatabaseJob.perform_now }
  end
end
