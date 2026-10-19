require "test_helper"
require "csv"

class Transactions::CsvExportTest < ActiveSupport::TestCase
  test "formats zero-decimal currency and transfer destination" do
    user = users(:one)
    source = user.financial_accounts.create!(name: "Yen bank", account_type: :bank, currency: "JPY")
    destination = user.financial_accounts.create!(name: "Yen cash", account_type: :cash, currency: "JPY")
    transfer = user.transactions.create!(kind: :transfer, amount_minor: 1_500, currency: "JPY",
      financial_account: source, transfer_account: destination, transaction_date: Date.new(2026, 8, 10))

    rows = CSV.parse(Transactions::CsvExport.generate([ transfer ]).delete_prefix("\uFEFF"), headers: true)

    assert_equal "1500", rows.first["Amount"]
    assert_equal "Yen cash", rows.first["Transfer account"]
    assert_equal "", rows.first["Category"]
  end
end
