class ReportsController < ApplicationController
  def show
    @month = report_month
    @currency = Current.user.default_currency
    @summary = MonthlyFinancialSummary.new(user: Current.user, month: @month, currency: @currency)
    @comparison = @summary.previous_comparison
    @trend = FinancialTrend.new(user: Current.user, currency: @currency, months: trend_months, ending_month: @month)
    @trend_activity = @trend.periods.any? { |period| period[:income_minor].nonzero? || period[:expense_minor].nonzero? }
    @categories = Current.user.available_categories(:expense).ordered
    @category = @categories.find_by(id: params[:category_id])
    @category_trend = @trend.category_periods(@category) if @category && @trend_activity
    snapshot_date = [ @month.end_of_month, Date.current ].min
    positions = NetWorthSummary.new(user: Current.user, as_of: snapshot_date).by_currency
    @position_currency = Current.user.default_currency
    @position = positions.fetch(@position_currency, { assets_minor: 0, liabilities_minor: 0, net_worth_minor: 0 })
  end

  private
    def report_month
      Date.new(params[:year].to_i, params[:month].to_i, 1)
    rescue Date::Error
      Date.current.beginning_of_month
    end

    def trend_months
      params[:range].to_i.presence_in([ 3, 6, 12 ]) || 6
    end
end
