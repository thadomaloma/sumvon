require "test_helper"

class FinanceToolsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
    @account = @user.financial_accounts.create!(name: "Tools bank", account_type: :bank, currency: "INR",
      opening_balance_minor: 10_000)
  end

  test "shows every finance tool" do
    get finance_tools_path

    assert_response :success
    assert_select "form[action=?]", account_reconciliations_path
    assert_select "form[action=?]", recurring_transactions_path
    assert_select "form[action=?]", monthly_closes_path
    assert_select "a[href=?]", new_transaction_import_path
  end

  test "reconciliation adjusts the balance without rewriting transactions" do
    assert_no_difference("@user.transactions.count") do
      post account_reconciliations_path, params: { account_reconciliation: { financial_account_id: @account.id,
        statement_balance: "125.50", reconciled_on: Date.current, note: "Bank statement" } }
    end

    assert_redirected_to finance_tools_path
    reconciliation = @user.account_reconciliations.last
    assert_equal 12_550, reconciliation.statement_balance_minor
    assert_equal 2_550, reconciliation.adjustment_minor
    assert_equal 12_550, @account.current_balance_minor
  end

  test "cannot reconcile another user's account" do
    other_account = users(:two).financial_accounts.create!(name: "Private", account_type: :bank, currency: "JPY")

    assert_no_difference("AccountReconciliation.count") do
      post account_reconciliations_path, params: { account_reconciliation: { financial_account_id: other_account.id,
        statement_balance: "100", reconciled_on: Date.current } }
    end
    assert_redirected_to finance_tools_path
  end

  test "cannot reconcile a closed month" do
    @user.monthly_closes.create!(year: Date.current.year, month: Date.current.month, currency: "INR",
      income_minor: 0, expense_minor: 0, net_minor: 0)

    assert_no_difference("@user.account_reconciliations.count") do
      post account_reconciliations_path, params: { account_reconciliation: { financial_account_id: @account.id,
        statement_balance: "125.50", reconciled_on: Date.current } }
    end

    assert_redirected_to finance_tools_path
    assert_equal I18n.t("reconciliations.invalid"), flash[:alert]
  end

  test "due generation reports an archived-account schedule without an error page" do
    category = Category.create!(name: "Archived schedule income", kind: :income)
    @user.recurring_transactions.create!(kind: :income, amount_minor: 100, currency: "INR",
      financial_account: @account, category:, frequency: :monthly, next_on: Date.current)
    @account.update!(archived: true)

    assert_no_difference("@user.transactions.count") { post recurring_transactions_run_path }
    assert_redirected_to finance_tools_path
    assert_match(/need attention/, flash[:alert])
  end
end
