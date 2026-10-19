class FinancialAlerts
  def initialize(user:) = @user = user

  def rows
    @rows ||= [ *overdrawn_accounts, *budget_alerts, *duplicate_alerts, *unusual_expenses ]
  end

  private
    attr_reader :user

    def overdrawn_accounts
      accounts = user.financial_accounts.active.ordered.to_a
      NetWorthSummary.new(user:, accounts:).assets.filter_map do |row|
        next unless row[:balance_minor].negative?
        { level: :danger, title: "#{row[:account].name} is overdrawn", detail: "Review recent activity or reconcile this account." }
      end
    end

    def budget_alerts
      user.budgets.for_period(Date.current).filter_map do |budget|
        summary = BudgetSummary.new(budget, spent_amount_minor: MonthlyFinancialSummary.new(user:, currency: budget.currency).expense_minor)
        next if summary.used_percentage < 80
        { level: summary.used_percentage >= 100 ? :danger : :warning, title: "Budget is #{summary.used_percentage}% used",
          detail: "#{budget.currency} spending is approaching the monthly plan." }
      end
    end

    def duplicate_alerts
      groups = user.transactions.where(transaction_date: 7.days.ago.to_date..Date.current)
        .group(:financial_account_id, :kind, :amount_minor, :transaction_date).having("COUNT(*) > 1").count
      groups.first(3).map { |_key, count| { level: :warning, title: "Possible duplicate transactions", detail: "#{count} matching entries were found." } }
    end

    def unusual_expenses
      expenses = user.transactions.expense.where(transaction_date: 90.days.ago.to_date..Date.current)
      average = expenses.average(:amount_minor).to_i
      return [] if average.zero?
      expenses.where("amount_minor >= ?", average * 3).recent_first.limit(3).map do |transaction|
        { level: :info, title: "Large expense recorded", detail: "#{transaction.description.presence || transaction.category.name} is above your recent average." }
      end
    end
end
