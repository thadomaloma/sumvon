class BudgetPerformance
  Period = Data.define(:month, :planned_minor, :spent_minor, :remaining_minor, :used_percentage, :status)

  def initialize(budget:, months: 6)
    @budget = budget
    @months = months.clamp(2, 12)
  end

  def call
    first_month = budget.reporting_month.prev_month(months - 1)
    plans = budget.user.budgets.where(currency: budget.currency)
      .where("(year * 100 + month) BETWEEN ? AND ?", month_key(first_month), month_key(budget.reporting_month))
      .index_by(&:reporting_month)
    spending = budget.user.transactions.expense.where(currency: budget.currency,
      transaction_date: first_month..budget.reporting_month.end_of_month)
      .group(:transaction_date).sum(:amount_minor)
      .each_with_object(Hash.new(0)) { |(date, amount), totals| totals[date.beginning_of_month] += amount }

    (0...months).reverse_each.map do |offset|
      month = budget.reporting_month.prev_month(offset)
      plan = plans[month]
      planned = plan&.planned_amount_minor.to_i
      spent = spending[month]
      used = percentage(spent, planned)
      Period.new(month:, planned_minor: planned, spent_minor: spent, remaining_minor: planned - spent,
        used_percentage: used, status: status_for(used))
    end
  end

  private
    attr_reader :budget, :months

    def month_key(date) = date.year * 100 + date.month
    def percentage(spent, planned)
      return spent.zero? ? 0.0 : 100.0 if planned.zero?
      ((spent.to_d / planned) * 100).round(1).to_f
    end

    def status_for(percentage)
      BudgetSummary::STATUSES.find { |range, _status| range.cover?(percentage) }.last
    end
end
