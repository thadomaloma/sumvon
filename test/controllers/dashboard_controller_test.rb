require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
    @inr_account = @user.financial_accounts.create!(name: "Chart bank", account_type: :bank, currency: "INR")
    @user.financial_accounts.create!(name: "Chart yen", account_type: :bank, currency: "JPY")
    income_category = Category.create!(name: "Chart income", kind: :income)
    expense_category = Category.create!(name: "Chart expense", kind: :expense)
    @user.transactions.create!(kind: :income, amount_minor: 50_000, currency: "INR", financial_account: @inr_account,
      category: income_category, transaction_date: Date.current.prev_month)
    @user.transactions.create!(kind: :expense, amount_minor: 20_000, currency: "INR", financial_account: @inr_account,
      category: expense_category, transaction_date: Date.current)
  end

  test "shows an accessible six-month cash-flow chart in the default currency" do
    get root_path

    assert_response :success
    assert_select "section#cash-flow-trend[data-currency=?]", @user.default_currency do
      assert_select "h2#cash-flow-trend-title", text: I18n.t("dashboard.cash_flow_trend")
      assert_select "select[name='trend_currency']", count: 0
      assert_select ".sr-only ul li", count: 6
      assert_select ".chart-income-bar", count: 6
      assert_select ".chart-expense-bar", count: 6
    end
  end

  test "shows only the user's default currency in financial position" do
    get root_path

    assert_select "section[data-position-currency=?]", @user.default_currency do
      assert_select ".financial-position-amount", count: 1, text: /INR/
      assert_select "select[name='position_currency']", count: 0
      assert_select "p", text: "Net account balance"
      assert_select "p", text: "All INR account balances minus credit-card dues"
    end
  end

  test "uses a compact monthly summary on mobile while preserving desktop cards" do
    get root_path

    assert_select "section[data-summary-layout='mobile'].md\\:hidden", count: 1 do
      assert_select "[data-metric='savings']", count: 1
      assert_select "[data-metric='income']", count: 1
      assert_select "[data-metric='expenses']", count: 1
    end
    assert_select "section[data-summary-layout='desktop'].hidden.md\\:block", count: 1 do
      assert_select "[data-metric='savings']", count: 1
      assert_select "[data-metric='income']", count: 1
      assert_select "[data-metric='expenses']", count: 1
    end
  end

  test "uses compact mobile dashboard actions and limits recent activity without changing desktop history" do
    6.times do |index|
      @user.transactions.create!(kind: :expense, amount_minor: 100 + index, currency: "INR",
        financial_account: @inr_account, category: Category.create!(name: "Recent #{index}", kind: :expense),
        transaction_date: Date.current)
    end

    get root_path

    assert_select "section[data-position-currency] a[href=?].md\\:hidden", financial_accounts_path, count: 1
    assert_select "[data-recent-layout='mobile'].md\\:hidden > a", count: 4
    assert_select "[data-recent-layout='desktop'].hidden.md\\:block > a", count: 6
  end

  test "does not allow a query parameter to change the financial-position currency" do
    get root_path, params: { position_currency: "JPY" }

    assert_select "section[data-position-currency=?]", @user.default_currency
    assert_select ".financial-position-amount", text: /INR/
  end

  test "ignores trend currency input and keeps the default currency" do
    get root_path, params: { trend_currency: "JPY" }
    assert_select "section#cash-flow-trend[data-currency=?]", @user.default_currency
    assert_select "select[name='trend_currency']", count: 0
  end

  test "the cash-flow trend is available to every authenticated user without a paywall" do
    get root_path

    assert_response :success
    assert_select "section#cash-flow-trend", count: 1
    assert_select "[data-premium-feature]", count: 0
  end

  test "the monthly snapshot explains spending dated after today is not in the balance yet" do
    travel_to Date.current.beginning_of_month + 9.days do
      # Setup dates its expense on the real today, which can fall after this travelled date.
      @user.transactions.expense.update_all(transaction_date: Date.current)
      @user.transactions.create!(kind: :expense, amount_minor: 3_050_000, currency: "INR", financial_account: @inr_account,
        category: Category.find_by!(name: "Chart expense"), transaction_date: Date.current + 5.days)

      get root_path

      note = "This month includes ₹30,500.00 in expenses dated after today. Your balance counts them from their date."
      assert_select "section[data-summary-layout='desktop'] [data-upcoming-note]", text: note
      assert_select "[data-upcoming-note].md\\:hidden", text: note
    end
  end

  test "the monthly snapshot has no upcoming note when nothing is dated after today" do
    get root_path

    assert_select "[data-upcoming-note]", count: 0
  end
end
