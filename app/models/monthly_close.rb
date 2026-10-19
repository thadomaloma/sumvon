class MonthlyClose < ApplicationRecord
  belongs_to :user

  validates :year, numericality: { only_integer: true, in: 2000..2200 }
  validates :month, numericality: { only_integer: true, in: 1..12 }
  validates :currency, inclusion: { in: MoneyAmount::CURRENCIES }
  validates :income_minor, :expense_minor, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :net_minor, numericality: { only_integer: true }
  validates :year, uniqueness: { scope: [ :user_id, :month ] }
  validate :period_is_not_in_the_future
  validate :net_matches_totals

  # Snapshots the month's totals in every currency the owner used, headlined by their
  # default currency. Locking the owner serializes this against new ledger entries.
  def self.close!(user:, period:)
    user.with_lock do
      currencies = user.transactions.in_month(period).distinct.pluck(:currency) | [ user.default_currency ]
      totals_by_currency = currencies.index_with do |currency|
        summary = MonthlyFinancialSummary.new(user:, month: period, currency:)
        { income_minor: summary.income_minor, expense_minor: summary.expense_minor, net_minor: summary.net_minor }
      end
      headline = totals_by_currency.fetch(user.default_currency)
      user.monthly_closes.create!(year: period.year, month: period.month, currency: user.default_currency,
        totals_by_currency:, **headline)
    end
  end

  def period = Date.new(year, month, 1)

  private
    def period_is_not_in_the_future
      errors.add(:base, "Future months cannot be closed") if year && month && period > Date.current.beginning_of_month
    rescue Date::Error
      # Numeric validations report invalid date components.
    end


    def net_matches_totals
      return unless income_minor.is_a?(Numeric) && expense_minor.is_a?(Numeric) && net_minor.is_a?(Numeric)
      errors.add(:net_minor, "must equal income minus expenses") unless net_minor == income_minor - expense_minor
    end
end
