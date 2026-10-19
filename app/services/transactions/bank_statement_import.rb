require "digest"

module Transactions
  class BankStatementImport
    Result = Data.define(:imported_count, :errors)
    BANKS = {
      "auto" => "Japanese bank",
      "japan_post" => "Japan Post Bank",
      "mufg" => "MUFG Bank",
      "mizuho" => "Mizuho Bank",
      "chiba_bank" => "Chiba Bank",
      "smbc" => "SMBC",
      "chiba_kogyo" => "Chiba Kogyo Bank"
    }.freeze
    ALLOWED_TYPES = {
      "auto" => %w[csv pdf],
      "japan_post" => %w[csv],
      "mufg" => %w[csv pdf],
      "mizuho" => %w[csv pdf],
      "chiba_bank" => %w[csv],
      "smbc" => %w[csv],
      "chiba_kogyo" => %w[csv pdf]
    }.freeze
    MAX_BYTES = 5.megabytes

    def self.call(user:, file:, bank:, financial_account_id:, income_category_id:, expense_category_id:)
      new(user:, file:, bank:, financial_account_id:, income_category_id:, expense_category_id:).call
    end

    def initialize(user:, file:, bank:, financial_account_id:, income_category_id:, expense_category_id:)
      @user = user
      @file = file
      @bank = bank.to_s
      @account = user.financial_accounts.active.find_by(id: financial_account_id)
      @income_category = user.available_categories(:income).find_by(id: income_category_id)
      @expense_category = user.available_categories(:expense).find_by(id: expense_category_id)
    end

    def call
      error = input_error
      return Result.new(imported_count: 0, errors: [ error ]) if error

      entries = parse_entries
      imported = 0
      errors = []
      occurrences = Hash.new(0)
      entries.each do |entry|
        fingerprint = Digest::SHA256.hexdigest([ @account.id, entry.date.iso8601, entry.kind,
          entry.amount, entry.description ].join("\0"))
        occurrences[fingerprint] += 1
        key = "bank-#{Digest::SHA256.hexdigest("#{fingerprint}\0#{occurrences[fingerprint]}").first(59)}"
        result = Transactions::Create.call(user: @user, source: "import", attributes: {
          kind: entry.kind, amount: entry.amount, financial_account_id: @account.id,
          category_id: category_for(entry).id, transaction_date: entry.date,
          description: entry.description.presence || BANKS.fetch(@bank), idempotency_key: key
        })
        if result.transaction.persisted?
          imported += 1 if result.created
        else
          errors << "Line #{entry.source_line} could not be imported: #{result.transaction.errors.full_messages.to_sentence}."
        end
      end
      Result.new(imported_count: imported, errors:)
    rescue JapanBankStatementParser::ParseError, PdfTextExtractor::ExtractionError => error
      Result.new(imported_count: 0, errors: [ error.message ])
    ensure
      @file.rewind if @file.respond_to?(:rewind)
    end

    private
      def input_error
        return "Choose a supported Japanese bank." unless BANKS.key?(@bank)
        return "Choose a bank statement file." unless @file
        return "Choose the Sumvon account that matches this statement." unless @account
        return "Choose default income and expense categories." unless @income_category && @expense_category
        return "Bank statements are limited to 5 MB." if file_size > MAX_BYTES
        "This bank does not support that statement format." unless ALLOWED_TYPES.fetch(@bank).include?(file_type)
      end

      def file_size
        return @file.size if @file.respond_to?(:size)
        @file.read(MAX_BYTES + 1).to_s.bytesize
      ensure
        @file.rewind if @file.respond_to?(:rewind)
      end

      def file_type
        File.extname(@file.original_filename.to_s).delete_prefix(".").downcase
      end

      def parse_entries
        if file_type == "pdf"
          JapanBankStatementParser.from_pdf_text(PdfTextExtractor.call(@file), bank: @bank)
        else
          JapanBankStatementParser.from_csv(@file.read(MAX_BYTES + 1), bank: @bank)
        end
      end

      def category_for(entry)
        entry.kind == :income ? @income_category : @expense_category
      end
  end
end
