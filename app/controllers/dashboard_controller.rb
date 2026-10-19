class DashboardController < ApplicationController
  def show
    all_accounts = Current.user.financial_accounts.ordered.to_a
    @accounts = all_accounts.reject(&:archived?)
    @net_worth = NetWorthSummary.new(user: Current.user, accounts: all_accounts)
    @balances_by_currency = @net_worth.by_currency.transform_values { |position| position[:net_worth_minor] }
    @position_currency = Current.user.default_currency
    @position_total = @balances_by_currency.fetch(@position_currency, 0)
    @summary = MonthlyFinancialSummary.new(user: Current.user, month: Date.current)
    @trend_currency = Current.user.default_currency
    @cash_flow_trend = FinancialTrend.new(user: Current.user, currency: @trend_currency, months: 6)
    @cash_flow_activity = @cash_flow_trend.periods.any? { |period| period[:income_minor].positive? || period[:expense_minor].positive? }
    @budget = Current.user.budgets.for_period(Date.current).find_by(currency: Current.user.default_currency)
    @budget_summary = BudgetSummary.new(@budget, spent_amount_minor: @summary.expense_minor) if @budget
    @recent_transactions = Current.user.transactions
      .includes(:financial_account, :transfer_account, :category).recent_first.limit(6).load
  end
end
