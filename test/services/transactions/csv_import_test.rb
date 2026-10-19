require "test_helper"
require "tempfile"

class Transactions::CsvImportTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @account = @user.financial_accounts.create!(name: "Import bank", account_type: :bank, currency: "INR")
    @category = Category.create!(name: "Import food", kind: :expense)
  end

  test "imports exported columns idempotently" do
    content = <<~CSV
      Date,Type,Amount,Currency,Account,Transfer account,Category,Description
      #{Date.current.iso8601},expense,12.50,INR,Import bank,,Import food,Lunch
    CSV
    file = uploaded_csv(content, filename: "history.csv")
    renamed_file = uploaded_csv(content, filename: "renamed.csv")

    first = Transactions::CsvImport.call(user: @user, file:)
    second = Transactions::CsvImport.call(user: @user, file: renamed_file)

    assert_empty first.errors, first.errors.inspect
    assert_equal 1, first.imported_count
    assert_equal 0, second.imported_count
    assert_empty second.errors
    assert_equal 1_250, @user.transactions.last.amount_minor
    assert @user.transactions.last.import?
  ensure
    file&.close!
    renamed_file&.close!
  end

  test "rejects missing columns and account currency mismatches" do
    missing = uploaded_csv("Date,Type\n#{Date.current.iso8601},expense\n")
    wrong_currency = uploaded_csv(<<~CSV)
      Date,Type,Amount,Currency,Category,Account,Transfer account,Description
      #{Date.current.iso8601},expense,12.50,JPY,Import food,Import bank,,Lunch
    CSV

    assert_match(/Missing CSV columns/, Transactions::CsvImport.call(user: @user, file: missing).errors.first)
    result = Transactions::CsvImport.call(user: @user, file: wrong_currency)
    assert_equal 0, result.imported_count
    assert_equal [ "Row 2 could not be imported." ], result.errors
  ensure
    missing&.close!
    wrong_currency&.close!
  end

  test "rejects an empty file without raising" do
    file = uploaded_csv("")

    result = Transactions::CsvImport.call(user: @user, file:)

    assert_equal 0, result.imported_count
    assert_match(/Missing CSV columns/, result.errors.first)
  ensure
    file&.close!
  end

  private
    def uploaded_csv(content, filename: "history.csv")
      Tempfile.new([ "sumvon-import", ".csv" ]).tap do |file|
        file.write(content)
        file.rewind
        file.define_singleton_method(:original_filename) { filename }
      end
    end
end
