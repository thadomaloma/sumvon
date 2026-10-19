require "test_helper"

class BudgetSummaryTest < ActiveSupport::TestCase
  test "can reuse a precomputed expense total" do
    summary = BudgetSummary.new(@budget, spent_amount_minor: 1_234)

    assert_equal 1_234, summary.spent_amount_minor
  end

  setup do
    @user = users(:one)
    @account = @user.financial_accounts.create!(name: "Budget bank", account_type: :bank, currency: "INR")
    @jpy_account = @user.financial_accounts.create!(name: "Budget yen", account_type: :bank, currency: "JPY")
    @food = Category.create!(name: "Food progress", kind: :expense)
    @transport = Category.create!(name: "Transport progress", kind: :expense)
    @income = Category.create!(name: "Salary progress", kind: :income)
    @budget = @user.budgets.create!(year: Date.current.year, month: Date.current.month, currency: "INR", planned_amount_minor: 100_000)
    @budget.budget_categories.create!(category: @food, planned_amount_minor: 20_000)
  end

  test "aggregates only matching expense month currency and user" do
    add(:expense, 15_000, @food)
    add(:income, 50_000, @income)
    add(:expense, 99_000, @food, date: Date.current.prev_month)
    add(:expense, 8_000, @food, account: @jpy_account, currency: "JPY")
    summary = BudgetSummary.new(@budget)

    assert_equal 15_000, summary.spent_amount_minor
    assert_equal 85_000, summary.remaining_amount_minor
    assert_equal 15.0, summary.used_percentage
    assert_equal :on_track, summary.status
    assert_equal 5_000, summary.category_progress.first[:remaining_amount_minor]
  end

  test "reports over-budget states without blocking spending" do
    add(:expense, 110_000, @food)
    summary = BudgetSummary.new(@budget)
    assert_equal :over_budget, summary.status
    assert_equal(-10_000, summary.remaining_amount_minor)
    assert_equal :over_budget, summary.category_progress.first[:status]
  end

  test "handles zero plan without division by zero" do
    @budget.budget_categories.destroy_all
    @budget.update!(planned_amount_minor: 0)
    assert_equal 0.0, BudgetSummary.new(@budget).used_percentage
    add(:expense, 100, @food)
    assert_equal 100.0, BudgetSummary.new(@budget).used_percentage
  end

  test "editing amount category and date immediately changes budget actuals" do
    transaction = add(:expense, 500, @food)
    transaction.update!(amount_minor: 700)
    assert_equal 700, BudgetSummary.new(@budget).spent_amount_minor
    transaction.update!(category: @transport)
    assert_equal 0, BudgetSummary.new(@budget).category_progress.first[:spent_amount_minor]
    transaction.update!(transaction_date: Date.current.next_month)
    assert_equal 0, BudgetSummary.new(@budget).spent_amount_minor
    transaction.destroy!
    assert_equal 0, BudgetSummary.new(@budget).spent_amount_minor
  end

  test "Plus rollover carries only the previous month's unused plan" do
    previous = @user.budgets.create!(year: Date.current.prev_month.year, month: Date.current.prev_month.month,
      currency: "INR", planned_amount_minor: 50_000)
    add(:expense, 20_000, @food, date: Date.current.prev_month)
    @budget.update!(rollover_enabled: true)

    summary = BudgetSummary.new(@budget)
    assert_equal 30_000, @budget.rollover_amount_minor
    assert_equal 130_000, summary.planned_amount_minor

    previous.update!(planned_amount_minor: 10_000)
    assert_equal 0, @budget.reload.rollover_amount_minor
  end

  private
    def add(kind, amount, category, date: Date.current, account: @account, currency: "INR")
      @user.transactions.create!(kind:, amount_minor: amount, category:, financial_account: account,
        currency:, transaction_date: date)
    end
end
