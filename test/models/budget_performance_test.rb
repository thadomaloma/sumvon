require "test_helper"

class BudgetPerformanceTest < ActiveSupport::TestCase
  test "compares six months without mixing users or currencies" do
    user = users(:one)
    account = user.financial_accounts.create!(name: "Planning bank", account_type: :bank, currency: "INR", opening_balance_minor: 100_000)
    category = Category.create!(name: "Planning expense", kind: :expense)
    budget = user.budgets.create!(year: Date.current.year, month: Date.current.month,
      currency: "INR", planned_amount_minor: 30_000)
    user.transactions.create!(kind: :expense, amount_minor: 12_000, financial_account: account,
      category:, currency: "INR", transaction_date: Date.current)
    other_account = users(:two).financial_accounts.create!(name: "Other planning", account_type: :bank, currency: "INR")
    other_category = users(:two).categories.create!(name: "Other planning", kind: :expense)
    users(:two).transactions.create!(kind: :expense, amount_minor: 99_000, financial_account: other_account,
      category: other_category, currency: "INR", transaction_date: Date.current)

    periods = BudgetPerformance.new(budget:).call

    assert_equal 6, periods.size
    assert_equal 12_000, periods.last.spent_minor
    assert_equal 18_000, periods.last.remaining_minor
    assert_equal :on_track, periods.last.status
  end
end
