require "csv"

module Transactions
  class CsvExport
    HEADERS = [ "Date", "Type", "Amount", "Currency", "Category", "Account", "Transfer account", "Description" ].freeze
    FORMULA_PREFIX = /\A(?:\s*[=+\-@]|[\t\r])/

    def self.generate(transactions)
      new(transactions).generate
    end

    def initialize(transactions)
      @transactions = transactions
    end

    def generate
      "\uFEFF" + CSV.generate(force_quotes: true) do |csv|
        csv << HEADERS
        transactions.each { |transaction| csv << row(transaction) }
      end
    end

    private
      attr_reader :transactions

      def row(transaction)
        [
          transaction.transaction_date.iso8601,
          transaction.kind,
          MoneyAmount.from_minor(transaction.amount_minor, transaction.currency),
          transaction.currency,
          safe_text(transaction.category&.name),
          safe_text(transaction.financial_account.name),
          safe_text(transaction.transfer_account&.name),
          safe_text(transaction.description)
        ]
      end

      def safe_text(value)
        text = value.to_s
        FORMULA_PREFIX.match?(text) ? "'#{text}" : text
      end
  end
end
