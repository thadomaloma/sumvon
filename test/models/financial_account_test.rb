require "test_helper"

class FinancialAccountTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @food = Category.create!(name: "Food test", kind: :expense)
    @salary = Category.create!(name: "Salary test", kind: :income)
    @cash = @user.financial_accounts.create!(name: "Cash", account_type: :cash, currency: "INR", opening_balance_minor: 10_000)
    @bank = @user.financial_accounts.create!(name: "Bank", account_type: :bank, currency: "INR")
  end

  test "income and expense produce a deterministic balance" do
    create_transaction(kind: :income, amount_minor: 5_000, category: @salary)
    create_transaction(kind: :expense, amount_minor: 2_000, category: @food)

    assert_equal 13_000, @cash.current_balance_minor
  end

  test "transfer moves balance without creating income or expense" do
    create_transaction(kind: :transfer, amount_minor: 3_000, transfer_account: @bank)

    assert_equal 7_000, @cash.current_balance_minor
    assert_equal 3_000, @bank.current_balance_minor
    assert_equal 0, MonthlyFinancialSummary.new(user: @user).income_minor
    assert_equal 0, MonthlyFinancialSummary.new(user: @user).expense_minor
  end

  test "liability balance becomes more negative with spending" do
    card = @user.financial_accounts.create!(name: "Card", account_type: :credit_card, currency: "INR", opening_balance_minor: -5_000)
    create_transaction(kind: :expense, amount_minor: 2_000, category: @food, financial_account: card)
    assert_equal(-7_000, card.current_balance_minor)
  end

  test "transactions before balance tracking starts remain historical and do not change balance" do
    historical = create_transaction(kind: :income, amount_minor: 50_000, category: @salary,
      transaction_date: Date.current.yesterday)
    @cash.update!(balance_started_on: Date.current, balance_anchor_transaction_id: historical.id)
    create_transaction(kind: :expense, amount_minor: 2_000, category: @food)

    assert_equal 8_000, @cash.current_balance_minor
  end

  test "a backdated transaction entered after the balance anchor changes the balance" do
    historical = create_transaction(kind: :income, amount_minor: 50_000, category: @salary,
      transaction_date: Date.current.yesterday)
    @cash.update!(balance_started_on: Date.current, balance_anchor_transaction_id: historical.id)

    create_transaction(kind: :expense, amount_minor: 2_000, category: @food,
      transaction_date: Date.current.yesterday)

    assert_equal 8_000, @cash.current_balance_minor
  end

  test "a backdated incoming transfer entered after the destination anchor changes its balance" do
    historical = create_transaction(kind: :income, amount_minor: 50_000, category: @salary,
      transaction_date: Date.current.yesterday)
    @bank.update!(opening_balance_minor: 20_000, balance_started_on: Date.current,
      balance_anchor_transaction_id: historical.id)

    create_transaction(kind: :transfer, amount_minor: 3_000, transfer_account: @bank,
      transaction_date: Date.current.yesterday)

    assert_equal 23_000, @bank.current_balance_minor
  end

  test "transactions on the balance start date are included" do
    @cash.update!(balance_started_on: Date.current)
    create_transaction(kind: :income, amount_minor: 5_000, category: @salary)

    assert_equal 15_000, @cash.current_balance_minor
  end

  test "incoming transfers respect the destination account balance start date" do
    historical = create_transaction(kind: :transfer, amount_minor: 3_000, transfer_account: @bank,
      transaction_date: Date.current.yesterday)
    @cash.update!(balance_started_on: Date.current, balance_anchor_transaction_id: historical.id)
    @bank.update!(opening_balance_minor: 20_000, balance_started_on: Date.current,
      balance_anchor_transaction_id: historical.id)

    assert_equal 10_000, @cash.current_balance_minor
    assert_equal 20_000, @bank.current_balance_minor
  end

  test "a balance requested before tracking began is unknown and treated as zero" do
    @cash.update!(balance_started_on: Date.current)

    assert_equal 0, @cash.current_balance_minor(as_of: Date.current.yesterday)
  end

  test "a credit card opening balance is entered as the amount owed" do
    card = @user.financial_accounts.create!(name: "Card", account_type: :credit_card, currency: "INR", opening_balance: "250.00")
    assert_equal(-25_000, card.opening_balance_minor)
    assert_equal 25_000, card.opening_balance_form_minor
  end

  test "a blank opening balance input keeps the stored balance" do
    @cash.update!(opening_balance: "")
    assert_equal 10_000, @cash.reload.opening_balance_minor
  end

  test "editing the opening balance anchors it to the current ledger position" do
    latest = create_transaction(kind: :expense, amount_minor: 1_000, category: @food)
    @cash.update!(opening_balance: "500")
    assert_equal latest.id, @cash.balance_anchor_transaction_id
  end

  test "reconciling records the adjustment that matches the statement" do
    create_transaction(kind: :expense, amount_minor: 2_000, category: @food)
    reconciliation = @cash.reconcile!(statement_balance: "70.00", reconciled_on: Date.current)
    assert_equal(-1_000, reconciliation.adjustment_minor)
    assert_equal 7_000, @cash.current_balance_minor
  end

  private
    def create_transaction(kind:, amount_minor:, category: nil, transfer_account: nil, financial_account: @cash,
      transaction_date: Date.current)
      @user.transactions.create!(kind:, amount_minor:, category:, transfer_account:, financial_account:,
        currency: financial_account.currency, transaction_date:)
    end
end
