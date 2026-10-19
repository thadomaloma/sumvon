class Transaction < ApplicationRecord
  include MoneyAttribute

  USER_SELECTABLE_KINDS = %w[income expense transfer].freeze

  normalizes :idempotency_key, with: ->(key) { key.presence }
  belongs_to :user
  belongs_to :financial_account
  belongs_to :transfer_account, class_name: "FinancialAccount", optional: true
  belongs_to :category, optional: true

  enum :kind, { income: "income", expense: "expense", transfer: "transfer" }, validate: true
  enum :source, { web: "web", import: "import" }, validate: true

  scope :recent_first, -> { order(transaction_date: :desc, created_at: :desc) }
  scope :in_month, ->(date) { where(transaction_date: date.beginning_of_month..date.end_of_month) }
  scope :through_date, ->(date) { where(transaction_date: ..date) }
  # Dated after today: listed and counted in period totals, but not yet in account balances.
  scope :upcoming, -> { where(transaction_date: Date.current.next_day..) }

  before_validation :normalize_for_kind
  money_attribute :amount
  before_destroy :ensure_period_open, unless: :destroyed_by_association

  validates :amount_minor, numericality: { only_integer: true, greater_than: 0 }
  validates :transaction_date, :currency, presence: true
  validates :description, length: { maximum: 240 }
  validates :idempotency_key, length: { maximum: 64 }, uniqueness: { scope: :user_id }, allow_nil: true
  validate :accounts_belong_to_user
  validate :accounts_are_active
  validate :period_is_open
  validate :currency_matches_accounts
  validate :category_matches_kind
  validate :correct_shape

  private
    # Forms submit every field regardless of kind, so keep only the references that make
    # sense for this kind and take the currency from the account the money moves through.
    def normalize_for_kind
      self.currency = financial_account.currency if financial_account
      self.category = nil if transfer?
      self.transfer_account = nil unless transfer?
    end

    def accounts_belong_to_user
      errors.add(:financial_account, "is not available") if financial_account && financial_account.user_id != user_id
      errors.add(:transfer_account, "is not available") if transfer_account && transfer_account.user_id != user_id
    end

    def accounts_are_active
      errors.add(:financial_account, "is archived") if financial_account&.archived? && will_save_change_to_financial_account_id?
      errors.add(:transfer_account, "is archived") if transfer_account&.archived? && will_save_change_to_transfer_account_id?
    end

    # A closed month is frozen: nothing may move into it or out of it.
    def period_is_open
      return unless user && transaction_date
      dates = [ transaction_date, transaction_date_in_database ].compact.uniq
      errors.add(:transaction_date, :closed_month) if dates.any? { |date| user.closed_month?(date) }
    end

    def ensure_period_open
      return unless user.closed_month?(transaction_date_in_database || transaction_date)
      errors.add(:transaction_date, :closed_month)
      throw :abort
    end

    def currency_matches_accounts
      return unless financial_account
      errors.add(:currency, "must match the account") if currency != financial_account.currency
      if transfer_account && transfer_account.currency != currency
        errors.add(:transfer_account, "must use the same currency until exchange rates are supported")
      end
    end

    def category_matches_kind
      return if transfer? || category.nil?
      errors.add(:category, "does not match the transaction type") if category.kind != kind
      errors.add(:category, "is not available") unless category.user_id.nil? || category.user_id == user_id
    end

    def correct_shape
      unless kind.in?(USER_SELECTABLE_KINDS)
        errors.add(:kind, "is not available")
        return
      end

      if transfer?
        errors.add(:transfer_account, "is required") if transfer_account.nil?
        errors.add(:transfer_account, "must be different") if transfer_account == financial_account
        errors.add(:category, "must be blank for a transfer") if category
      else
        errors.add(:category, "is required") if category.nil?
        errors.add(:transfer_account, "must be blank") if transfer_account
      end
    end
end
