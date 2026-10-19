class FinancialTrend
  attr_reader :user, :currency, :months, :ending_month

  def initialize(user:, currency: user.default_currency, months: 6, ending_month: Date.current)
    @user = user
    @currency = currency
    @months = months.to_i.clamp(3, 12)
    @ending_month = ending_month.to_date.beginning_of_month
  end

  def periods
    @periods ||= month_range.map do |month|
      values = grouped.fetch(month, {})
      income = values.fetch("income", 0)
      expense = values.fetch("expense", 0)
      { month:, income_minor: income, expense_minor: expense, savings_minor: income - expense }
    end
  end

  def category_periods(category)
    values = user.transactions.expense.where(currency:, category:)
      .where(transaction_date: month_range.first..month_range.last.end_of_month)
      .group(:transaction_date)
      .sum(:amount_minor)
      .each_with_object(Hash.new(0)) { |(date, amount), totals| totals[date.beginning_of_month] += amount }
    month_range.map { |month| { month:, amount_minor: values.fetch(month, 0) } }
  end

  private
    def month_range
      @month_range ||= (0...months).map { |offset| ending_month.prev_month(offset) }.reverse
    end

    def grouped
      @grouped ||= begin
        rows = user.transactions.where(currency:, kind: %w[income expense])
          .where(transaction_date: month_range.first..month_range.last.end_of_month)
          .group(:transaction_date, :kind)
          .sum(:amount_minor)
        rows.each_with_object({}) do |((date, kind), amount), result|
          month = result[date.beginning_of_month] ||= Hash.new(0)
          month[kind] += amount
        end
      end
    end
end
