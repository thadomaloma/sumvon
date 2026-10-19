require "test_helper"

class NetWorthSummaryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @cash = @user.financial_accounts.create!(name: "Worth cash", account_type: :cash, currency: "INR", opening_balance_minor: 100_000)
    @bank = @user.financial_accounts.create!(name: "Worth bank", account_type: :bank, currency: "INR")
    @card = @user.financial_accounts.create!(name: "Worth card", account_type: :credit_card, currency: "INR", opening_balance_minor: -20_000)
    @yen = @user.financial_accounts.create!(name: "Worth yen", account_type: :savings, currency: "JPY", opening_balance_minor: 50_000)
    @expense = Category.create!(name: "Worth expense", kind: :expense)
  end

  test "calculates assets liabilities and net worth separately by currency" do
    position = NetWorthSummary.new(user: @user).by_currency
    assert_equal 100_000, position["INR"][:assets_minor]
    assert_equal 20_000, position["INR"][:liabilities_minor]
    assert_equal 80_000, position["INR"][:net_worth_minor]
    assert_equal 50_000, position["JPY"][:net_worth_minor]
  end

  test "accepts preloaded accounts without changing the calculation" do
    accounts = @user.financial_accounts.ordered.to_a

    assert_equal NetWorthSummary.new(user: @user).by_currency,
      NetWorthSummary.new(user: @user, accounts:).by_currency
  end

  test "asset transfer does not change net worth" do
    @user.transactions.create!(kind: :transfer, amount_minor: 30_000, financial_account: @cash,
      transfer_account: @bank, currency: "INR", transaction_date: Date.current)
    assert_equal 80_000, NetWorthSummary.new(user: @user).by_currency["INR"][:net_worth_minor]
  end

  test "expense and liability spending reduce net worth" do
    @user.transactions.create!(kind: :expense, amount_minor: 5_000, financial_account: @cash,
      category: @expense, currency: "INR", transaction_date: Date.current)
    @user.transactions.create!(kind: :expense, amount_minor: 3_000, financial_account: @card,
      category: @expense, currency: "INR", transaction_date: Date.current)
    assert_equal 72_000, NetWorthSummary.new(user: @user).by_currency["INR"][:net_worth_minor]
  end

  test "archived nonzero accounts remain included and future transactions are excluded" do
    @user.transactions.create!(kind: :expense, amount_minor: 99_000, financial_account: @cash,
      category: @expense, currency: "INR", transaction_date: Date.current.next_month)
    @cash.update!(archived: true)
    assert_equal 80_000, NetWorthSummary.new(user: @user).by_currency["INR"][:net_worth_minor]
    assert_equal 100_000, @cash.current_balance_minor
  end

  test "a positive credit-card overpayment contributes to assets" do
    @card.update!(opening_balance_minor: 5_000)
    position = NetWorthSummary.new(user: @user).by_currency["INR"]
    assert_equal 105_000, position[:assets_minor]
    assert_equal 0, position[:liabilities_minor]
    assert_equal 105_000, position[:net_worth_minor]
  end

  test "uses each account's balance start date for primary and incoming activity" do
    historical_expense = @user.transactions.create!(kind: :expense, amount_minor: 9_000, financial_account: @cash,
      category: @expense, currency: "INR", transaction_date: Date.current.yesterday)
    historical_transfer = @user.transactions.create!(kind: :transfer, amount_minor: 7_000, financial_account: @cash,
      transfer_account: @bank, currency: "INR", transaction_date: Date.current.yesterday)
    anchor_id = [ historical_expense.id, historical_transfer.id ].max
    @cash.update!(balance_started_on: Date.current, balance_anchor_transaction_id: anchor_id)
    @bank.update!(opening_balance_minor: 30_000, balance_started_on: Date.current,
      balance_anchor_transaction_id: anchor_id)

    position = NetWorthSummary.new(user: @user).by_currency["INR"]

    assert_equal 110_000, position[:net_worth_minor]
    assert_equal @cash.current_balance_minor,
      NetWorthSummary.new(user: @user).account_rows.find { |row| row[:account] == @cash }[:balance_minor]
    assert_equal @bank.current_balance_minor,
      NetWorthSummary.new(user: @user).account_rows.find { |row| row[:account] == @bank }[:balance_minor]
  end

  test "does not report an account position before its balance start date" do
    tomorrow = Date.current.tomorrow
    @cash.update!(balance_started_on: tomorrow)

    row = NetWorthSummary.new(user: @user, as_of: Date.current).account_rows.find { |entry| entry[:account] == @cash }

    assert_equal 0, row[:balance_minor]
  end

  test "includes a backdated transaction created after an account's ledger anchor" do
    historical = @user.transactions.create!(kind: :expense, amount_minor: 9_000, financial_account: @cash,
      category: @expense, currency: "INR", transaction_date: Date.current.yesterday)
    @cash.update!(balance_started_on: Date.current, balance_anchor_transaction_id: historical.id)

    @user.transactions.create!(kind: :expense, amount_minor: 5_000, financial_account: @cash,
      category: @expense, currency: "INR", transaction_date: Date.current.yesterday)

    cash_row = NetWorthSummary.new(user: @user).account_rows.find { |row| row[:account] == @cash }
    assert_equal 95_000, cash_row[:balance_minor]
    assert_equal @cash.current_balance_minor, cash_row[:balance_minor]
  end
end
