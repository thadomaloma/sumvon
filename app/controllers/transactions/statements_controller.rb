class Transactions::StatementsController < ApplicationController
  include TransactionFiltering

  BREAKDOWN_ROWS = 5

  def show
    @transactions = filtered_transactions.includes(:financial_account, :transfer_account, :category).recent_first.to_a
    @period_label = parsed_month ? I18n.l(parsed_month, format: "%B %Y") : t("transactions.statement.all_time")
    @filter_labels = filter_labels
    @totals = totals(@transactions)
    render layout: "printable"
  end

  private
    def filter_labels
      labels = []
      labels << t("transactions.statement.type_filter", type: params[:kind].humanize) if params[:kind].in?(Transaction::USER_SELECTABLE_KINDS)
      account = Current.user.financial_accounts.find_by(id: params[:account_id])
      labels << t("transactions.statement.account_filter", account: account.name) if account
      category = Current.user.available_categories.find_by(id: params[:category_id])
      labels << t("transactions.statement.category_filter", category: category.name) if category
      labels
    end

    def totals(transactions)
      transactions.group_by(&:currency).transform_values do |currency_transactions|
        upcoming = currency_transactions.select { |transaction| transaction.transaction_date > Date.current && !transaction.transfer? }
        {
          income: currency_transactions.select(&:income?).sum(&:amount_minor),
          expenses: currency_transactions.select(&:expense?).sum(&:amount_minor),
          upcoming_income: upcoming.select(&:income?).sum(&:amount_minor),
          upcoming_expenses: upcoming.select(&:expense?).sum(&:amount_minor),
          upcoming_count: upcoming.size,
          breakdown: category_breakdown(currency_transactions)
        }
      end
    end

    # Spending by category, or income by category when the statement has no spending.
    # Keeps the largest four and folds the rest into "Other" so the chart stays readable.
    def category_breakdown(transactions)
      kind = transactions.any?(&:expense?) ? :expense : (transactions.any?(&:income?) ? :income : nil)
      return unless kind

      selected = transactions.select { |transaction| transaction.kind == kind.to_s }
      total = selected.sum(&:amount_minor)
      rows = selected.group_by { |transaction| transaction.category&.name || t("transactions.statement.uncategorized") }
        .map { |name, items| { name:, amount_minor: items.sum(&:amount_minor) } }
        .sort_by { |row| [ -row[:amount_minor], row[:name] ] }
      if rows.size > BREAKDOWN_ROWS
        rest = rows.drop(BREAKDOWN_ROWS - 1)
        rows = rows.first(BREAKDOWN_ROWS - 1) << { name: t("transactions.statement.other_categories", count: rest.size), amount_minor: rest.sum { |row| row[:amount_minor] }, other: true }
      end
      rows.each { |row| row[:percentage] = total.zero? ? 0 : (row[:amount_minor].to_d / total * 100).round(1).to_f }
      { kind:, total_minor: total, rows: }
    end
end
