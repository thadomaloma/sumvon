require "test_helper"

class MonthlyClosesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
    @account = @user.financial_accounts.create!(name: "Close bank", account_type: :bank, currency: "INR")
    @category = Category.create!(name: "Close expense", kind: :expense)
    @transaction = @user.transactions.create!(kind: :expense, amount_minor: 500, currency: "INR",
      financial_account: @account, category: @category, transaction_date: Date.current)
  end

  test "closing a month snapshots totals and blocks transaction changes" do
    post monthly_closes_path, params: { monthly_close: { period: Date.current.strftime("%Y-%m") } }
    close = @user.monthly_closes.last
    assert_equal 500, close.expense_minor

    assert_no_difference("@user.transactions.count") do
      post transactions_path, params: { transaction: { kind: "expense", amount: "2", financial_account_id: @account.id,
        category_id: @category.id, transaction_date: Date.current } }
    end
    assert_redirected_to transactions_path

    delete transaction_path(@transaction)
    assert @transaction.reload.persisted?
  end

  test "closing a month snapshots each transaction currency" do
    jpy_account = @user.financial_accounts.create!(name: "Close yen", account_type: :bank, currency: "JPY")
    jpy_category = Category.create!(name: "Close yen income", kind: :income)
    @user.transactions.create!(kind: :income, amount_minor: 2_000, currency: "JPY",
      financial_account: jpy_account, category: jpy_category, transaction_date: Date.current)

    post monthly_closes_path, params: { monthly_close: { period: Date.current.strftime("%Y-%m") } }

    totals = @user.monthly_closes.last.totals_by_currency
    assert_equal 500, totals.fetch("INR").fetch("expense_minor")
    assert_equal 2_000, totals.fetch("JPY").fetch("income_minor")
  end

  test "reopening allows transaction changes again" do
    close = @user.monthly_closes.create!(year: Date.current.year, month: Date.current.month, currency: "INR",
      income_minor: 0, expense_minor: 500, net_minor: -500)
    delete monthly_close_path(close)

    delete transaction_path(@transaction)
    assert_not Transaction.exists?(@transaction.id)
  end

  test "does not close a future month" do
    assert_no_difference("@user.monthly_closes.count") do
      post monthly_closes_path, params: { monthly_close: { period: Date.current.next_month.strftime("%Y-%m") } }
    end
    assert_redirected_to finance_tools_path
  end
end
