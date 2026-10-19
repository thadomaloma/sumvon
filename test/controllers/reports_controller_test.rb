require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  test "report requires authentication" do
    get monthly_report_path(2026, 8)
    assert_redirected_to new_session_path
  end

  test "report only aggregates the signed-in user's data" do
    user = users(:one)
    other = users(:two)
    category = Category.create!(name: "Report request", kind: :expense)
    account = user.financial_accounts.create!(name: "User report", account_type: :bank, currency: "INR")
    other_account = other.financial_accounts.create!(name: "Other report", account_type: :bank, currency: "JPY")
    user.transactions.create!(kind: :expense, amount_minor: 500, category:, financial_account: account,
      currency: "INR", transaction_date: Date.new(2026, 8, 1))
    other_category = other.categories.create!(name: "Other private report", kind: :expense)
    other.transactions.create!(kind: :expense, amount_minor: 90_000, category: other_category,
      financial_account: other_account, currency: "JPY", transaction_date: Date.new(2026, 8, 1))
    sign_in_as user
    get monthly_report_path(2026, 8, currency: "JPY")
    assert_response :success
    assert_select "select[name='currency']", count: 0
    assert_select "body", text: /₹5\.00/
    assert_select "body", { text: /¥90,000/, count: 0 }
  end

  test "empty report does not render a zero-filled trend chart" do
    user = users(:one)
    sign_in_as user
    get monthly_report_path(2026, 8)
    assert_response :success
    assert_select "h2", { text: "Financial trends", count: 0 }
    assert_select "h2", text: /No activity recorded/
  end

  test "financial position shows only the user's default currency" do
    user = users(:one)
    balance_started_on = Date.new(2026, 8, 1)
    user.financial_accounts.create!(name: "Default bank", account_type: :bank, currency: "INR",
      opening_balance_minor: 12_500, balance_started_on:)
    user.financial_accounts.create!(name: "Foreign bank", account_type: :bank, currency: "JPY",
      opening_balance_minor: 90_000, balance_started_on:)
    sign_in_as user

    get monthly_report_path(2026, 8)

    assert_response :success
    assert_select "section[data-report-position][data-position-currency='INR']", count: 1 do
      assert_select "p", text: /₹125\.00 INR/
      assert_select "*", text: /JPY|¥90,000/, count: 0
    end
  end

  test "every authenticated user sees the full report without any paywall" do
    user = users(:one)
    account = user.financial_accounts.create!(name: "Free report", account_type: :bank, currency: "INR")
    category = Category.create!(name: "Free report expense", kind: :expense)
    user.transactions.create!(kind: :expense, amount_minor: 500, category:, financial_account: account,
      currency: "INR", transaction_date: Date.new(2026, 8, 1))
    sign_in_as user

    get monthly_report_path(2026, 8)

    assert_response :success
    assert_select "[data-premium-feature]", count: 0
    assert_select "h2", text: /Where your money went/
    assert_select "h2", text: /Compared with the previous month/
    assert_select "[data-report-position]", count: 1
  end
end
