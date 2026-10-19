class FinanceToolsController < ApplicationController
  def show
    @accounts = Current.user.financial_accounts.active.ordered
    @categories = Current.user.available_categories.ordered
    @recurring_transactions = Current.user.recurring_transactions.includes(:financial_account, :category).order(:next_on)
    @forecast = CashFlowForecast.new(user: Current.user)
    @alerts = FinancialAlerts.new(user: Current.user).rows
    @monthly_closes = Current.user.monthly_closes.order(year: :desc, month: :desc)
  end
end
