class RecurringTransactions::RunsController < ApplicationController
  def create
    generated = 0
    failures = 0
    Current.user.recurring_transactions.active.find_each do |rule|
      generated += rule.run_due!
    rescue ActiveRecord::RecordInvalid
      failures += 1
    end
    if failures.positive?
      redirect_to finance_tools_path, alert: t("recurring.generated_with_failures", count: generated, failures:)
    else
      redirect_to finance_tools_path, notice: t("recurring.generated", count: generated)
    end
  end
end
