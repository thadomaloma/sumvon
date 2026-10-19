class BudgetSummary
  STATUSES = {
    0...75 => :on_track,
    75...90 => :watch,
    90...100 => :near_limit,
    100..Float::INFINITY => :over_budget
  }.freeze

  attr_reader :budget
  delegate :currency, :reporting_month, to: :budget

  def initialize(budget, spent_amount_minor: nil, include_rollover: true)
    @budget = budget
    @spent_amount_minor = spent_amount_minor
    @include_rollover = include_rollover
  end

  def planned_amount_minor = @include_rollover ? budget.effective_planned_amount_minor : budget.planned_amount_minor

  def spent_amount_minor
    return @spent_amount_minor unless @spent_amount_minor.nil?

    @spent_amount_minor = expenses.sum(:amount_minor)
  end

  def remaining_amount_minor
    planned_amount_minor - spent_amount_minor
  end

  def used_percentage
    percentage(spent_amount_minor, planned_amount_minor)
  end

  def status
    STATUSES.find { |range, _status| range.cover?(used_percentage) }.last
  end

  def category_progress
    actuals = expenses.group(:category_id).sum(:amount_minor)
    budget.budget_categories.includes(:category).sort_by { |allocation| -allocation.planned_amount_minor }.map do |allocation|
      actual = actuals.fetch(allocation.category_id, 0)
      {
        allocation:,
        category: allocation.category,
        planned_amount_minor: allocation.planned_amount_minor,
        spent_amount_minor: actual,
        remaining_amount_minor: allocation.planned_amount_minor - actual,
        used_percentage: percentage(actual, allocation.planned_amount_minor),
        status: status_for(actual, allocation.planned_amount_minor)
      }
    end
  end

  def days_remaining(today = Date.current)
    return 0 if today > reporting_month.end_of_month
    [ (reporting_month.end_of_month - [ today, reporting_month ].max).to_i, 0 ].max
  end

  private
    def expenses
      budget.user.transactions.expense.in_month(reporting_month).where(currency:)
    end

    def percentage(actual, planned)
      return actual.zero? ? 0.0 : 100.0 if planned.zero?
      ((actual.to_d / planned) * 100).round(1).to_f
    end

    def status_for(actual, planned)
      value = percentage(actual, planned)
      STATUSES.find { |range, _status| range.cover?(value) }.last
    end
end
