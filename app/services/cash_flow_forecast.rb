class CashFlowForecast
  attr_reader :user, :from, :through

  def initialize(user:, from: Date.current, days: 90)
    @user = user
    @from = from.to_date
    @through = @from + days.days
  end

  def by_currency
    rows.group_by { |row| row[:currency] }.transform_values do |items|
      { income_minor: items.select { |row| row[:kind] == "income" }.sum { |row| row[:amount_minor] },
        expense_minor: items.select { |row| row[:kind] == "expense" }.sum { |row| row[:amount_minor] },
        transfer_minor: items.select { |row| row[:kind] == "transfer" }.sum { |row| row[:amount_minor] },
        occurrences: items.size }
    end
  end

  def rows
    @rows ||= user.recurring_transactions.active.flat_map do |rule|
      date = rule.next_on
      skipped = 0
      while date < from && skipped < 10_000
        date = rule.advance(date)
        skipped += 1
      end
      next [] if date < from

      occurrences = []
      while date <= through && occurrences.size < 120
        occurrences << { date:, kind: rule.kind, amount_minor: rule.amount_minor, currency: rule.currency,
          description: rule.description.presence || rule.kind.humanize }
        date = rule.advance(date)
      end
      occurrences
    end.sort_by { |row| row[:date] }
  end
end
