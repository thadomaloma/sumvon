class MonthlyFinancialSummary
  attr_reader :user, :month, :currency

  def initialize(user:, month: Date.current, currency: user.default_currency)
    @user = user
    @month = month.to_date.beginning_of_month
    @currency = currency
  end

  def income_minor = totals.fetch("income", 0)
  def expense_minor = totals.fetch("expense", 0)
  def net_minor = income_minor - expense_minor
  alias_method :savings_amount_minor, :net_minor

  def savings_rate
    return nil if income_minor.zero?
    ((savings_amount_minor.to_d / income_minor) * 100).round(1).to_f
  end

  def activity?
    ordinary.exists?
  end

  def category_breakdown
    @category_breakdown ||= begin
      rows = ordinary.expense.joins(:category)
        .group("categories.id", "categories.name")
        .order(Arel.sql("SUM(transactions.amount_minor) DESC"))
        .pluck("categories.id", "categories.name", Arel.sql("SUM(transactions.amount_minor)"),
          Arel.sql("COUNT(transactions.id)"))
      rows.map do |category_id, name, amount, count|
        {
          category_id:,
          name:,
          amount_minor: amount,
          transaction_count: count,
          percentage: expense_minor.zero? ? 0.0 : ((amount.to_d / expense_minor) * 100).round(1).to_f
        }
      end
    end
  end

  # Income and expenses in this month dated after today. They count in the month's
  # totals but not in account balances until their date arrives.
  def upcoming
    @upcoming ||= begin
      sums = ordinary.upcoming.group(:kind).sum(:amount_minor)
      { income_minor: sums.fetch("income", 0), expense_minor: sums.fetch("expense", 0), count: ordinary.upcoming.count }
    end
  end

  def previous
    self.class.new(user:, month: month.prev_month, currency:)
  end

  def previous_comparison
    return nil unless previous.activity?
    {
      income_difference_minor: income_minor - previous.income_minor,
      expense_difference_minor: expense_minor - previous.expense_minor,
      savings_difference_minor: savings_amount_minor - previous.savings_amount_minor
    }
  end

  private
    def totals
      @totals ||= ordinary.group(:kind).sum(:amount_minor)
    end

    def ordinary
      user.transactions.where(kind: %w[income expense]).in_month(month).where(currency:)
    end
end
