require "test_helper"

class BudgetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
    @food = Category.create!(name: "Budget request food", kind: :expense)
  end

  test "creates a budget and category allocation from major-unit inputs" do
    assert_difference("@user.budgets.count") do
      post budgets_path, params: { budget: { reporting_month: "2026-08", year: 2026, month: 8,
        currency: "INR", planned_amount: "300.00", allocations: { @food.id.to_s => "80.00" } } }
    end
    budget = @user.budgets.last
    assert_equal 30_000, budget.planned_amount_minor
    assert_equal 8_000, budget.budget_categories.first.planned_amount_minor
    assert_redirected_to budget_path(budget)
  end

  test "rejects a malformed category allocation instead of silently dropping it" do
    post budgets_path, params: { budget: { reporting_month: "2026-08", currency: "INR",
      planned_amount: "100", allocations: { @food.id.to_s => "12.345" } } }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /allocation must use valid digits/
  end

  test "copy pre-fills planned values without creating a budget" do
    source = @user.budgets.create!(year: 2026, month: 7, currency: "INR", planned_amount_minor: 30_000)
    source.budget_categories.create!(category: @food, planned_amount_minor: 8_000)
    assert_no_difference("@user.budgets.count") do
      get new_budget_path(month: "2026-08", copy_from: source.id)
    end
    assert_response :success
    assert_select "input[name='budget[planned_amount]'][value='300.00']"
    assert_select "input[name='budget[allocations][#{@food.id}]'][value='80.00']"
  end

  test "another user cannot access a budget" do
    budget = @user.budgets.create!(year: 2026, month: 8, currency: "INR", planned_amount_minor: 30_000)
    sign_out
    sign_in_as users(:two)
    get budget_path(budget)
    assert_response :not_found
  end

  test "rejects an invalid reporting month even if hidden values are tampered" do
    assert_no_difference("@user.budgets.count") do
      post budgets_path, params: { budget: { reporting_month: "not-a-month", year: 2026, month: 8,
        currency: "INR", planned_amount: "300", allocations: {} } }
    end
    assert_response :unprocessable_entity
  end
end
