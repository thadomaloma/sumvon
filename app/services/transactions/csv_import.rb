require "csv"
require "digest"

module Transactions
  class CsvImport
    Result = Data.define(:imported_count, :errors)
    MAX_ROWS = 1_000
    MAX_BYTES = 2.megabytes
    REQUIRED_HEADERS = Transactions::CsvExport::HEADERS.freeze

    def self.call(user:, file:) = new(user:, file:).call

    def initialize(user:, file:)
      @user = user
      @file = file
    end

    def call
      return Result.new(imported_count: 0, errors: [ "Choose a CSV file." ]) unless @file

      contents = @file.read(MAX_BYTES + 1).to_s
      return Result.new(imported_count: 0, errors: [ "CSV is limited to 2 MB." ]) if contents.bytesize > MAX_BYTES

      rows = CSV.parse(contents.sub(/\A\uFEFF/, ""), headers: true, encoding: "UTF-8")
      missing_headers = REQUIRED_HEADERS - Array(rows.headers).compact
      if missing_headers.any?
        return Result.new(imported_count: 0, errors: [ "Missing CSV columns: #{missing_headers.join(", ")}." ])
      end
      return Result.new(imported_count: 0, errors: [ "CSV is limited to #{MAX_ROWS} rows." ]) if rows.size > MAX_ROWS

      imported = 0
      errors = []
      occurrences = Hash.new(0)
      rows.each_with_index do |row, index|
        fingerprint = Digest::SHA256.hexdigest(REQUIRED_HEADERS.map { |header| clean(row[header]) }.join("\0"))
        occurrences[fingerprint] += 1
        case import_row(row, fingerprint:, occurrence: occurrences[fingerprint])
        when :created then imported += 1
        when :invalid then errors << "Row #{index + 2} could not be imported."
        end
      rescue CSV::MalformedCSVError, ArgumentError
        errors << "Row #{index + 2} contains invalid data."
      end
      Result.new(imported_count: imported, errors:)
    rescue CSV::MalformedCSVError, EncodingError, ArgumentError
      Result.new(imported_count: 0, errors: [ "The CSV file is invalid or is not UTF-8." ])
    ensure
      @file.rewind if @file.respond_to?(:rewind)
    end

    private
      def import_row(row, fingerprint:, occurrence:)
        account = @user.financial_accounts.active.find_by(name: clean(row["Account"]))
        kind = clean(row["Type"]).downcase
        category = @user.available_categories.find_by(name: clean(row["Category"])) unless kind == "transfer"
        transfer_account = @user.financial_accounts.active.find_by(name: clean(row["Transfer account"])) if kind == "transfer"
        return :invalid if account && clean(row["Currency"]) != account.currency

        key = "csv-#{fingerprint.first(54)}-#{occurrence}"
        result = Transactions::Create.call(user: @user, source: "import", attributes: { kind:, amount: clean(row["Amount"]),
          financial_account_id: account&.id, transfer_account_id: transfer_account&.id, category_id: category&.id,
          transaction_date: Date.iso8601(clean(row["Date"])),
          description: clean(row["Description"]), idempotency_key: key })
        return :invalid unless result.transaction.persisted?
        result.created ? :created : :skipped
      end

      def clean(value) = value.to_s.delete_prefix("'").strip
  end
end
