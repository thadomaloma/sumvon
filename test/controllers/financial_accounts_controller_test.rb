require "test_helper"

class FinancialAccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "index lists only the current user's accounts" do
    mine = @user.financial_accounts.create!(name: "My Cash", account_type: :cash, currency: "INR")
    other = users(:two).financial_accounts.create!(name: "Other Cash", account_type: :cash, currency: "JPY")

    get financial_accounts_path

    assert_response :success
    assert_match mine.name, response.body
    assert_no_match other.name, response.body
  end

  test "creates an account converting the opening balance from major units" do
    assert_difference("@user.financial_accounts.count") do
      post financial_accounts_path, params: { financial_account: { name: "Main Bank", account_type: "bank",
        currency: "INR", opening_balance: "500.25", balance_started_on: Date.current.yesterday } }
    end
    account = @user.financial_accounts.last
    assert_equal 50_025, account.opening_balance_minor
    assert_equal Date.current.yesterday, account.balance_started_on
    assert_redirected_to financial_account_path(account)
  end

  test "rejects an invalid opening balance instead of silently saving zero" do
    assert_no_difference("@user.financial_accounts.count") do
      post financial_accounts_path, params: { financial_account: { name: "Invalid amount", account_type: "bank",
        currency: "INR", opening_balance: "12.345", balance_started_on: Date.current } }
    end

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Opening balance must use valid digits/
  end

  test "stores a positive credit card amount owed as a negative ledger balance" do
    post financial_accounts_path, params: { financial_account: { name: "Card", account_type: "credit_card",
      currency: "INR", opening_balance: "527.82", balance_started_on: Date.current } }

    account = @user.financial_accounts.last
    assert_equal(-52_782, account.opening_balance_minor)
    assert_equal 52_782, account.opening_balance_form_minor
  end

  test "show paginates account activity and scopes to the current user" do
    account = @user.financial_accounts.create!(name: "History", account_type: :bank, currency: "INR")
    category = Category.create!(name: "Financial account show", kind: :expense)
    @user.transactions.create!(kind: :expense, amount_minor: 100, financial_account: account,
      category:, currency: "INR", transaction_date: Date.current)

    get financial_account_path(account)

    assert_response :success
  end

  test "updates an account's name and currency" do
    account = @user.financial_accounts.create!(name: "Old Name", account_type: :cash, currency: "INR")

    patch financial_account_path(account), params: { financial_account: { name: "New Name",
      account_type: "cash", currency: "INR", opening_balance: "0" } }

    assert_redirected_to financial_account_path(account)
    assert_equal "New Name", account.reload.name
  end

  test "editing the balance basis anchors existing backdated activity" do
    account = @user.financial_accounts.create!(name: "Rebased", account_type: :cash, currency: "INR")
    category = Category.create!(name: "Rebase income", kind: :income)
    historical = @user.transactions.create!(kind: :income, amount_minor: 5_000, financial_account: account,
      category:, currency: "INR", transaction_date: Date.current.yesterday)

    patch financial_account_path(account), params: { financial_account: { name: account.name,
      account_type: account.account_type, currency: account.currency, opening_balance: "100",
      balance_started_on: Date.current } }

    account.reload
    assert_equal historical.id, account.balance_anchor_transaction_id
    assert_equal 10_000, account.current_balance_minor
  end

  test "does not allow currency changes after ledger activity exists" do
    account = @user.financial_accounts.create!(name: "Ledger", account_type: :cash, currency: "INR")
    category = Category.create!(name: "Currency lock expense", kind: :expense)
    @user.transactions.create!(kind: :expense, amount_minor: 500, financial_account: account,
      category: category, currency: "INR", transaction_date: Date.current)

    patch financial_account_path(account), params: { financial_account: { name: account.name,
      account_type: account.account_type, currency: "JPY", opening_balance: "0", balance_started_on: Date.current } }

    assert_response :unprocessable_entity
    assert_equal "INR", account.reload.currency
    assert_select "[role=alert]", text: /Currency cannot be changed/
  end

  test "archives and restores an account" do
    account = @user.financial_accounts.create!(name: "Toggle Me", account_type: :cash, currency: "INR")

    post financial_account_archive_path(account)
    assert account.reload.archived?
    assert_equal "Account archived.", flash[:notice]

    post financial_account_archive_path(account)
    assert account.reload.archived?, "archiving twice must not restore the account"

    delete financial_account_archive_path(account)
    assert_not account.reload.archived?
    assert_equal "Account restored.", flash[:notice]
  end

  test "another user cannot view, edit, or archive this user's account" do
    account = @user.financial_accounts.create!(name: "Private", account_type: :cash, currency: "INR")
    sign_out
    sign_in_as users(:two)

    get financial_account_path(account)
    assert_response :not_found

    patch financial_account_path(account), params: { financial_account: { name: "Hijacked" } }
    assert_response :not_found

    post financial_account_archive_path(account)
    assert_response :not_found
    delete financial_account_archive_path(account)
    assert_response :not_found
  end
end
