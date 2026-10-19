class RecurringTransaction < ApplicationRecord
  include MoneyAttribute

  belongs_to :user
  belongs_to :financial_account
  belongs_to :transfer_account, class_name: "FinancialAccount", optional: true
  belongs_to :category, optional: true

  enum :kind, { income: "income", expense: "expense", transfer: "transfer" }, validate: true
  enum :frequency, { weekly: "weekly", monthly: "monthly", yearly: "yearly" }, validate: true
  scope :active, -> { where(active: true) }

  before_validation :normalize_for_kind
  money_attribute :amount

  validates :amount_minor, numericality: { only_integer: true, greater_than: 0 }
  validates :currency, inclusion: { in: MoneyAmount::CURRENCIES }
  validates :next_on, presence: true
  validates :description, length: { maximum: 240 }
  validate :valid_shape

  def advance(date)
    case frequency
    when "weekly" then date + 1.week
    when "monthly" then date.next_month
    when "yearly" then date.next_year
    end
  end

  def run_due!(through: Date.current)
    generated = 0
    processed = 0
    with_lock do
      while active? && next_on <= through && processed < 120
        result = Transactions::Create.call(user:, attributes: transaction_attributes(next_on))
        raise ActiveRecord::RecordInvalid, result.transaction unless result.transaction.persisted?
        self.next_on = advance(next_on)
        generated += 1 if result.created
        processed += 1
      end
      save!
    end
    generated
  end

  private
    def normalize_for_kind
      self.currency = financial_account.currency if financial_account
      self.category = nil if transfer?
      self.transfer_account = nil unless transfer?
    end

    def transaction_attributes(date)
      { kind:, amount_minor:, financial_account_id:, transfer_account_id:, category_id:,
        transaction_date: date, description:, idempotency_key: "recurring-#{id}-#{date.iso8601}" }
    end

    def valid_shape
      errors.add(:financial_account, "is not available") if financial_account && financial_account.user_id != user_id
      errors.add(:currency, "must match the account") if financial_account && currency != financial_account.currency
      errors.add(:transfer_account, "is not available") if transfer_account && transfer_account.user_id != user_id
      if category && !(category.user_id.nil? || category.user_id == user_id)
        errors.add(:category, "is not available")
      end
      if transfer?
        errors.add(:transfer_account, "is required") unless transfer_account
        errors.add(:transfer_account, "must be different") if transfer_account == financial_account
        errors.add(:transfer_account, "must use the same currency") if transfer_account && transfer_account.currency != currency
        errors.add(:category, "must be blank") if category
      else
        errors.add(:category, "is required") unless category
        errors.add(:transfer_account, "must be blank") if transfer_account
        errors.add(:category, "does not match the transaction type") if category && category.kind != kind
      end
    end
end
