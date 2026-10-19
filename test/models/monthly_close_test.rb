require "test_helper"

class MonthlyCloseTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @food = Category.create!(name: "Close food", kind: :expense)
    @cash = @user.financial_accounts.create!(name: "Close cash", account_type: :cash, currency: "INR")
    @yen = @user.financial_accounts.create!(name: "Close yen", account_type: :cash, currency: "JPY")
  end

  test "close snapshots totals for every currency used in the month" do
    period = Date.current.prev_month.beginning_of_month
    @user.transactions.create!(kind: :expense, amount_minor: 1_500, financial_account: @cash, category: @food, transaction_date: period)
    @user.transactions.create!(kind: :expense, amount_minor: 900, financial_account: @yen, category: @food, transaction_date: period)

    close = MonthlyClose.close!(user: @user, period:)

    assert_equal [ period.year, period.month ], [ close.year, close.month ]
    assert_equal 900, close.reload.totals_by_currency.dig("JPY", "expense_minor")
    assert_equal @user.default_currency, close.currency
  end
end
