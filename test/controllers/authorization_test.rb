require "test_helper"

class AuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @intruder = users(:two)
    @account = @owner.financial_accounts.create!(name: "Private bank", account_type: :bank, currency: "INR")
    @category = Category.create!(name: "Private expense", kind: :expense)
    @transaction = @owner.transactions.create!(financial_account: @account, category: @category, kind: :expense,
      amount_minor: 500, currency: "INR", transaction_date: Date.current)
  end

  test "guests are redirected to sign in" do
    get financial_accounts_path
    assert_redirected_to new_session_path
  end

  test "guests cannot view budgets" do
    get budgets_path
    assert_redirected_to new_session_path
  end

  test "another user cannot read an account" do
    sign_in_as @intruder
    get financial_account_path(@account)
    assert_response :not_found
  end

  test "another user cannot edit a transaction" do
    sign_in_as @intruder
    get edit_transaction_path(@transaction)
    assert_response :not_found
  end

  test "another user cannot update or delete a transaction" do
    sign_in_as @intruder
    patch transaction_path(@transaction), params: { transaction: { kind: "expense", amount: "999",
      financial_account_id: @account.id, category_id: @category.id, transaction_date: Date.current } }
    assert_response :not_found
    assert_equal 500, @transaction.reload.amount_minor

    assert_no_difference("Transaction.count") do
      delete transaction_path(@transaction)
    end
    assert_response :not_found
  end

  test "another user cannot edit or update a financial account" do
    sign_in_as @intruder
    get edit_financial_account_path(@account)
    assert_response :not_found

    patch financial_account_path(@account), params: { financial_account: { name: "Hijacked" } }
    assert_response :not_found
    assert_not_equal "Hijacked", @account.reload.name
  end

  test "another user cannot view, edit, update, or delete a budget" do
    budget = @owner.budgets.create!(year: Date.current.year, month: Date.current.month, currency: "INR", planned_amount_minor: 10_000)
    sign_in_as @intruder
    get budget_path(budget)
    assert_response :not_found
    get edit_budget_path(budget)
    assert_response :not_found

    patch budget_path(budget), params: { budget: { planned_amount: "99999" } }
    assert_response :not_found
    assert_equal 10_000, budget.reload.planned_amount_minor

    assert_no_difference("Budget.count") do
      delete budget_path(budget)
    end
    assert_response :not_found
  end

  test "another user cannot delete an account holding a transaction, only their own" do
    sign_in_as @intruder
    post financial_account_archive_path(@account)
    assert_response :not_found
  end
end
