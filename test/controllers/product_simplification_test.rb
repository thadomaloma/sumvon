require "test_helper"

# Covers the product simplification: AI Assistant, WhatsApp, Plan, Stripe billing,
# and money movements were removed; every remaining feature is free for any
# authenticated user.
class ProductSimplificationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "old Plan URLs return the normal application 404, not a redirect" do
    %w[/automation /savings_goals /savings_goals/new /recurring_items /recurring_items/new
       /recurring_occurrences].each do |path|
      get path
      assert_response :not_found, "expected 404 for #{path}"
    end
  end

  test "old billing and Stripe URLs return the normal application 404" do
    %w[/billing /premium_features/advanced_reports /checkout_session /billing_portal_session].each do |path|
      get path
      assert_response :not_found, "expected 404 for #{path}"
    end
  end

  test "the Stripe webhook route no longer exists" do
    post "/webhooks/stripe"
    assert_response :not_found
  end

  test "retired money-movement URLs return the normal application 404" do
    %w[/money_movements /money_movements/new /money_movements/1].each do |path|
      get path
      assert_response :not_found, "expected 404 for #{path}"
    end
  end

  test "retired AI Assistant and WhatsApp URLs return the normal application 404" do
    %w[/assistant /assistant_messages /pending_ai_actions/1/confirm /whatsapp_connection
       /webhooks/whatsapp].each do |path|
      get path
      assert_response :not_found, "expected 404 for #{path}"
    end
  end

  test "Plan links do not appear in desktop or mobile navigation" do
    get root_path
    assert_response :success
    assert_no_match(/Goals & planning|Plan ahead calmly/i, response.body)
    assert_select "a[href='/automation']", count: 0
    assert_select "a[href='/savings_goals']", count: 0
    assert_select "a[href='/billing']", count: 0
    assert_select "a[href='/money_movements']", count: 0
    assert_select "a[href='/assistant']", count: 0
    assert_select "a[href='/whatsapp_connection']", count: 0
  end

  test "billing and upgrade text does not appear anywhere in settings" do
    get settings_path
    assert_response :success
    assert_no_match(/Upgrade|Subscribe|Manage subscription|Sumvon Plus|Free plan|Premium|Trial/i, response.body)
  end

  test "reports, budgets, and transaction exports are fully available without a subscription" do
    account = @user.financial_accounts.create!(name: "Free account", account_type: :bank, currency: "INR")
    category = Category.create!(name: "Free category", kind: :expense)
    @user.transactions.create!(kind: :expense, amount_minor: 500, financial_account: account, category:,
      currency: "INR", transaction_date: Date.current)

    get monthly_report_path(Date.current.year, Date.current.month)
    assert_response :success
    assert_select "[data-premium-feature]", count: 0
    assert_no_match(/upgrade to|sumvon plus|unlock/i, response.body)

    get transactions_path(format: :csv)
    assert_response :success

    get transactions_statement_path
    assert_response :success

    budget = @user.budgets.create!(year: Date.current.year, month: Date.current.month, currency: "INR",
      planned_amount_minor: 10_000)
    budget.budget_categories.create!(category:, planned_amount_minor: 5_000)
    get budget_path(budget)
    assert_response :success
    assert_select "h2", text: /Category progress/
    assert_select "[data-premium-feature]", count: 0
  end

  test "no premium-feature paywall markers remain anywhere in the app" do
    get root_path
    assert_select "[data-premium-feature]", count: 0
  end
end
