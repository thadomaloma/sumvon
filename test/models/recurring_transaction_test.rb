require "test_helper"

class RecurringTransactionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @account = @user.financial_accounts.create!(name: "Recurring bank", account_type: :bank, currency: "INR")
    @category = Category.create!(name: "Recurring salary", kind: :income)
  end

  test "generates every due occurrence once" do
    rule = @user.recurring_transactions.create!(kind: :income, amount_minor: 5_000, currency: "INR",
      financial_account: @account, category: @category, frequency: :weekly, next_on: Date.current - 7.days,
      description: "Weekly pay")

    assert_equal 2, rule.run_due!
    assert_equal 2, @user.transactions.where(description: "Weekly pay").count
    assert_equal 0, rule.run_due!
    assert_operator rule.reload.next_on, :>, Date.current
  end

  test "forecast expands future occurrences by currency" do
    @user.recurring_transactions.create!(kind: :income, amount_minor: 5_000, currency: "INR",
      financial_account: @account, category: @category, frequency: :monthly, next_on: Date.current.next_month)

    forecast = CashFlowForecast.new(user: @user, days: 70).by_currency.fetch("INR")
    assert_equal 2, forecast[:occurrences]
    assert_equal 10_000, forecast[:income_minor]
  end

  test "forecast separates transfers from expenses" do
    destination = @user.financial_accounts.create!(name: "Forecast savings", account_type: :savings, currency: "INR")
    @user.recurring_transactions.create!(kind: :transfer, amount_minor: 7_000, currency: "INR",
      financial_account: @account, transfer_account: destination, frequency: :monthly, next_on: Date.current.next_month)

    forecast = CashFlowForecast.new(user: @user, days: 40).by_currency.fetch("INR")
    assert_equal 0, forecast[:expense_minor]
    assert_equal 7_000, forecast[:transfer_minor]
  end

  test "forecast advances overdue schedules into its future window" do
    @user.recurring_transactions.create!(kind: :income, amount_minor: 5_000, currency: "INR",
      financial_account: @account, category: @category, frequency: :weekly, next_on: Date.current - 15.days)

    rows = CashFlowForecast.new(user: @user, from: Date.current, days: 14).rows

    assert_equal 2, rows.size
    assert rows.all? { |row| row[:date] >= Date.current }
  end

  test "rejects another user's transfer account and private category" do
    other = users(:two)
    other_account = other.financial_accounts.create!(name: "Other destination", account_type: :bank, currency: "INR")
    other_category = Category.create!(name: "Other private income", kind: :income, user: other)

    transfer = @user.recurring_transactions.new(kind: :transfer, amount_minor: 100, currency: "INR",
      financial_account: @account, transfer_account: other_account, frequency: :monthly, next_on: Date.current)
    income = @user.recurring_transactions.new(kind: :income, amount_minor: 100, currency: "INR",
      financial_account: @account, category: other_category, frequency: :monthly, next_on: Date.current)

    assert_not transfer.valid?
    assert transfer.errors[:transfer_account].present?
    assert_not income.valid?
    assert income.errors[:category].present?
  end

  test "closed months reject due generation" do
    @user.monthly_closes.create!(year: Date.current.year, month: Date.current.month, currency: "INR",
      income_minor: 0, expense_minor: 0, net_minor: 0)
    rule = @user.recurring_transactions.create!(kind: :income, amount_minor: 5_000, currency: "INR",
      financial_account: @account, category: @category, frequency: :monthly, next_on: Date.current)

    assert_no_difference("@user.transactions.count") do
      assert_raises(ActiveRecord::RecordInvalid) { rule.run_due! }
    end
  end
end
