require "test_helper"

class FinancialReportTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @account = @user.financial_accounts.create!(name: "Report bank", account_type: :bank, currency: "INR")
    @food = Category.create!(name: "Food report", kind: :expense)
    @salary = Category.create!(name: "Salary report", kind: :income)
  end

  test "savings and savings rate use income minus expenses" do
    add(:income, 40_000, @salary)
    add(:expense, 30_000, @food)
    summary = MonthlyFinancialSummary.new(user: @user)
    assert_equal 10_000, summary.savings_amount_minor
    assert_equal 25.0, summary.savings_rate
  end

  test "savings rate is unavailable with zero income and supports negative cash flow" do
    add(:expense, 5_000, @food)
    summary = MonthlyFinancialSummary.new(user: @user)
    assert_nil summary.savings_rate
    add(:income, 2_000, @salary)
    assert_equal(-150.0, MonthlyFinancialSummary.new(user: @user).savings_rate)
  end

  test "comparison and category breakdown use adjacent calendar months" do
    add(:income, 20_000, @salary, date: Date.current.prev_month)
    add(:expense, 8_000, @food, date: Date.current.prev_month)
    add(:income, 30_000, @salary)
    add(:expense, 7_000, @food)
    summary = MonthlyFinancialSummary.new(user: @user)
    assert_equal 10_000, summary.previous_comparison[:income_difference_minor]
    assert_equal(-1_000, summary.previous_comparison[:expense_difference_minor])
    assert_equal 7_000, summary.category_breakdown.first[:amount_minor]
    assert_equal 1, summary.category_breakdown.first[:transaction_count]
  end

  test "first and last dates remain in the intended report month and transfers are excluded" do
    month = Date.new(2026, 8, 1)
    add(:expense, 100, @food, date: month)
    add(:expense, 200, @food, date: month.end_of_month)
    destination = @user.financial_accounts.create!(name: "Report cash", account_type: :cash, currency: "INR")
    @user.transactions.create!(kind: :transfer, amount_minor: 9_000, financial_account: @account,
      transfer_account: destination, currency: "INR", transaction_date: month)
    assert_equal 300, MonthlyFinancialSummary.new(user: @user, month:).expense_minor
  end

  test "trend returns structured zero-filled periods and category history" do
    add(:expense, 500, @food, date: Date.current.prev_month)
    trend = FinancialTrend.new(user: @user, months: 3)
    assert_equal 3, trend.periods.length
    assert_equal 500, trend.category_periods(@food)[1][:amount_minor]
  end

  private
    def add(kind, amount, category, date: Date.current)
      @user.transactions.create!(kind:, amount_minor: amount, category:, financial_account: @account,
        currency: "INR", transaction_date: date)
    end
end
