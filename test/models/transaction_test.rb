require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @other = users(:two)
    @account = @user.financial_accounts.create!(name: "Main", account_type: :bank, currency: "INR")
    @other_account = @other.financial_accounts.create!(name: "Other", account_type: :bank, currency: "JPY")
    @expense_category = Category.create!(name: "Expense test", kind: :expense)
    @income_category = Category.create!(name: "Income test", kind: :income)
  end

  test "requires positive integer minor units" do
    transaction = build_transaction(amount_minor: 0)
    assert_not transaction.valid?
    assert transaction.errors.added?(:amount_minor, :greater_than, value: 0, count: 0)
  end

  test "prevents cross-user account access" do
    transaction = build_transaction(financial_account: @other_account, currency: "JPY")
    assert_not transaction.valid?
    assert transaction.errors[:financial_account].present?
  end

  test "prevents cross-currency transfers" do
    transaction = build_transaction(kind: :transfer, category: nil, transfer_account: @other_account)
    assert_not transaction.valid?
    assert transaction.errors[:transfer_account].present?
  end

  test "category must match transaction kind" do
    transaction = build_transaction(kind: :income, category: @expense_category)
    assert_not transaction.valid?
    assert transaction.errors[:category].present?
  end

  test "converts a decimal amount in the account currency" do
    transaction = build_transaction(amount_minor: nil, amount: "472.50")
    assert transaction.valid?
    assert_equal 47_250, transaction.amount_minor
  end

  test "reports an amount that does not fit the currency precision" do
    transaction = build_transaction(amount_minor: nil, amount: "1.999")
    assert_not transaction.valid?
    assert transaction.errors.added?(:amount, :invalid_money)
    assert_empty transaction.errors[:amount_minor]
  end

  test "drops references that do not apply to the kind and takes the account currency" do
    destination = @user.financial_accounts.create!(name: "Savings", account_type: :savings, currency: "INR")
    transaction = build_transaction(kind: :transfer, currency: nil, transfer_account: destination)
    assert transaction.valid?
    assert_nil transaction.category
    assert_equal "INR", transaction.currency
  end

  test "cannot move into an archived account" do
    archived = @user.financial_accounts.create!(name: "Old", account_type: :cash, currency: "INR", archived: true)
    transaction = build_transaction(financial_account: archived)
    assert_not transaction.valid?
    assert transaction.errors[:financial_account].present?
  end

  test "a closed month cannot be edited into, out of, or deleted from" do
    transaction = build_transaction(transaction_date: Date.current.prev_month)
    transaction.save!
    close_month(Date.current.prev_month)

    assert_not transaction.update(transaction_date: Date.current)
    assert transaction.errors.added?(:transaction_date, :closed_month)
    assert_not transaction.reload.destroy
    assert Transaction.exists?(transaction.id)
    assert_not build_transaction(transaction_date: Date.current.prev_month).valid?
  end

  private
    def close_month(date)
      @user.monthly_closes.create!(year: date.year, month: date.month, currency: "INR",
        income_minor: 0, expense_minor: 0, net_minor: 0)
    end

    def build_transaction(**attributes)
      defaults = { user: @user, financial_account: @account, kind: :expense, amount_minor: 100,
        currency: "INR", category: @expense_category, transaction_date: Date.current }
      Transaction.new(defaults.merge(attributes))
    end
end
