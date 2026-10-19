require "test_helper"

class MonthlyFinancialSummaryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @account = @user.financial_accounts.create!(name: "Main", account_type: :bank, currency: "INR")
    @food = Category.create!(name: "Food summary", kind: :expense)
    @housing = Category.create!(name: "Housing summary", kind: :expense)
    @salary = Category.create!(name: "Salary summary", kind: :income)
  end

  test "calculates monthly totals and category grouping while excluding other months" do
    add(:income, 100_000, @salary, Date.current)
    add(:expense, 20_000, @food, Date.current)
    add(:expense, 5_000, @housing, Date.current)
    add(:expense, 99_000, @food, Date.current.prev_month)
    summary = MonthlyFinancialSummary.new(user: @user)

    assert_equal 100_000, summary.income_minor
    assert_equal 25_000, summary.expense_minor
    assert_equal 75_000, summary.net_minor
    assert_equal({ "Food summary" => 20_000, "Housing summary" => 5_000 }, summary.category_breakdown.to_h { |row| [ row[:name], row[:amount_minor] ] })
  end

  test "reports income and expenses dated after today separately as upcoming" do
    travel_to Date.new(2026, 8, 10) do
      add(:income, 100_000, @salary, Date.new(2026, 8, 2))
      add(:expense, 20_000, @food, Date.new(2026, 8, 10))
      add(:expense, 7_000, @housing, Date.new(2026, 8, 25))
      add(:income, 1_000, @salary, Date.new(2026, 8, 31))
      summary = MonthlyFinancialSummary.new(user: @user)

      assert_equal 27_000, summary.expense_minor
      assert_equal({ income_minor: 1_000, expense_minor: 7_000, count: 2 }, summary.upcoming)
    end
  end

  test "a transfer-only month has no income or expense activity" do
    destination = @user.financial_accounts.create!(name: "Transfer destination", account_type: :bank, currency: "INR")
    @user.transactions.create!(kind: :transfer, amount_minor: 5_000, financial_account: @account,
      transfer_account: destination, currency: "INR", transaction_date: Date.current)

    summary = MonthlyFinancialSummary.new(user: @user)
    assert_not summary.activity?
    assert_equal 0, summary.income_minor
    assert_equal 0, summary.expense_minor
  end

  test "editing a transaction immediately changes derived totals" do
    transaction = add(:expense, 500, @food, Date.current)
    transaction.update!(amount_minor: 700)
    assert_equal 700, MonthlyFinancialSummary.new(user: @user).expense_minor
  end

  private
    def add(kind, amount, category, date)
      @user.transactions.create!(kind:, amount_minor: amount, category:, financial_account: @account,
        currency: "INR", transaction_date: date)
    end
end
