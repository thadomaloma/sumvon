require "test_helper"

class BudgetTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @food = Category.create!(name: "Food budget", kind: :expense)
    @income = Category.create!(name: "Income budget", kind: :income)
  end

  test "prevents duplicate currency budget for a month" do
    create_budget
    duplicate = @user.budgets.new(year: Date.current.year, month: Date.current.month, currency: "INR", planned_amount_minor: 10_000)
    assert_not duplicate.valid?
    assert duplicate.errors[:currency].present?
  end

  test "category allocations can be partial but cannot exceed total" do
    budget = create_budget
    budget.budget_categories.build(category: @food, planned_amount_minor: 60_000)
    assert_not budget.valid?
    assert budget.errors[:budget_categories].present?
  end

  test "rejects income and another user's categories" do
    budget = create_budget
    assert_not budget.budget_categories.create(category: @income, planned_amount_minor: 1_000).persisted?
    other_category = users(:two).categories.create!(name: "Private budget", kind: :expense)
    assert_not budget.budget_categories.create(category: other_category, planned_amount_minor: 1_000).persisted?
  end

  test "months are historically independent" do
    august = create_budget(month: 8)
    august.budget_categories.create!(category: @food, planned_amount_minor: 10_000)
    september = @user.budgets.create!(year: Date.current.year, month: 9, currency: "INR", planned_amount_minor: august.planned_amount_minor)
    august.budget_categories.each { |item| september.budget_categories.create!(category: item.category, planned_amount_minor: item.planned_amount_minor) }
    september.update!(planned_amount_minor: 40_000)
    assert_equal 50_000, august.reload.planned_amount_minor
    assert_equal 10_000, august.budget_categories.first.planned_amount_minor
  end

  test "assigns month and allocations from form input" do
    budget = @user.budgets.new(reporting_month: "2026-08", currency: "INR", planned_amount: "300.00",
      allocations: { @food.id.to_s => "80.00" })
    assert budget.save
    assert_equal [ 2026, 8 ], [ budget.year, budget.month ]
    assert_equal 8_000, budget.budget_categories.sole.planned_amount_minor

    assert budget.update(allocations: { @food.id.to_s => "" })
    assert_empty budget.reload.budget_categories
  end

  test "rejects malformed allocations and months" do
    budget = @user.budgets.new(reporting_month: "nope", currency: "INR", planned_amount: "100",
      allocations: { @food.id.to_s => "12.345" })
    assert_not budget.valid?
    assert budget.errors[:reporting_month].present?
    assert budget.errors.added?(:base, :invalid_allocation, category: @food.name)
  end

  test "ignores allocations for categories the owner cannot use" do
    other_category = users(:two).categories.create!(name: "Private budget", kind: :expense)
    budget = @user.budgets.create!(year: 2026, month: 8, currency: "INR", planned_amount: "100",
      allocations: { other_category.id.to_s => "10", @income.id.to_s => "10" })
    assert_empty budget.budget_categories
  end

  private
    def create_budget(month: Date.current.month)
      @user.budgets.create!(year: Date.current.year, month:, currency: "INR", planned_amount_minor: 50_000)
    end
end
