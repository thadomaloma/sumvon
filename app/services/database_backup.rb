require "zlib"

# Copies the primary SQLite database to Cloudflare R2, so a backup survives losing the
# Railway volume or project. VACUUM INTO writes a consistent snapshot while the app keeps
# running; the snapshot is integrity-checked and gzipped before upload. Old backups are
# expired by a lifecycle rule on the bucket, so the R2 token only needs to write objects.
class DatabaseBackup
  REQUIRED_ENV = %w[R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET].freeze

  class Error < StandardError; end

  def self.configured? = REQUIRED_ENV.all? { |name| ENV[name].present? }

  def initialize(client: nil, bucket: ENV["R2_BUCKET"], now: Time.current)
    @client = client
    @bucket = bucket
    @now = now
  end

  def call
    Dir.mktmpdir("database-backup") do |dir|
      snapshot = File.join(dir, "primary.sqlite3")
      connection.execute("VACUUM INTO #{connection.quote(snapshot)}")
      verify!(snapshot)

      archive = "#{snapshot}.gz"
      Zlib::GzipWriter.open(archive) { |gzip| File.open(snapshot, "rb") { |file| IO.copy_stream(file, gzip) } }
      File.open(archive, "rb") do |body|
        client.put_object(bucket:, key:, body:, content_type: "application/gzip")
      end
      key
    end
  end

  def key
    "sqlite/#{Rails.env}/primary-#{now.utc.strftime('%Y%m%dT%H%M%SZ')}.sqlite3.gz"
  end

  private
    attr_reader :bucket, :now

    def connection = ActiveRecord::Base.connection

    def verify!(snapshot)
      result = nil
      SQLite3::Database.new(snapshot, readonly: true) { |db| result = db.get_first_value("PRAGMA integrity_check") }
      raise Error, "Backup snapshot failed its integrity check: #{result}" unless result == "ok"
    end

    def client
      @client ||= begin
        require "aws-sdk-s3"
        Aws::S3::Client.new(
          region: "auto",
          endpoint: "https://#{ENV.fetch('R2_ACCOUNT_ID')}.r2.cloudflarestorage.com",
          access_key_id: ENV.fetch("R2_ACCESS_KEY_ID"),
          secret_access_key: ENV.fetch("R2_SECRET_ACCESS_KEY"),
          request_checksum_calculation: "when_required",
          response_checksum_validation: "when_required"
        )
      end
    end
end
