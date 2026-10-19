class FinancialAccount < ApplicationRecord
  include MoneyAttribute

  attribute :balance_started_on, :date, default: -> { Date.current }

  belongs_to :user
  has_many :transactions, dependent: :restrict_with_error
  has_many :incoming_transfers, class_name: "Transaction", foreign_key: :transfer_account_id, dependent: :restrict_with_error
  has_many :account_reconciliations, dependent: :destroy

  enum :account_type, {
    cash: "cash", bank: "bank", savings: "savings", e_wallet: "e_wallet",
    credit_card: "credit_card", other: "other"
  }, validate: true

  scope :active, -> { where(archived: false) }
  scope :ordered, -> { order(:name) }

  money_attribute :opening_balance, minor: :opening_balance_form_minor, keep_if_blank: true
  before_save :anchor_balance_basis, if: :balance_basis_changed?

  validates :name, presence: true, length: { maximum: 80 }
  validates :currency, inclusion: { in: MoneyAmount::CURRENCIES }
  validates :opening_balance_minor, numericality: { only_integer: true }
  validates :balance_anchor_transaction_id, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :balance_started_on, presence: true
  validate :currency_unchanged_after_activity, on: :update

  ASSET_TYPES = %w[cash bank savings e_wallet other].freeze
  LIABILITY_TYPES = %w[credit_card].freeze

  def current_balance_minor(as_of: Date.current)
    as_of = as_of.to_date
    return 0 if as_of < balance_started_on

    visible = balance_activity(transactions, as_of:)
    visible_incoming = balance_activity(incoming_transfers, as_of:)

    opening_balance_minor +
      visible.income.sum(:amount_minor) -
      visible.expense.sum(:amount_minor) -
      visible.transfer.sum(:amount_minor) +
      visible_incoming.transfer.sum(:amount_minor) +
      account_reconciliations.where(reconciled_on: balance_started_on..as_of).sum(:adjustment_minor)
  end

  # Liabilities are entered as the positive amount owed but stored as a negative balance.
  def opening_balance_form_minor
    liability? ? -opening_balance_minor : opening_balance_minor
  end

  def opening_balance_form_minor=(value)
    self.opening_balance_minor = value && liability? ? -value : value
  end

  # Serialized with the owner's ledger so the adjustment is computed against a balance
  # no concurrent transaction can change underneath it.
  def reconcile!(**attributes)
    user.with_lock do
      lock!
      account_reconciliations.create!(user:, **attributes)
    end
  end

  def liability?
    credit_card?
  end

  def asset?
    ASSET_TYPES.include?(account_type)
  end

  private
    def balance_basis_changed?
      new_record? || will_save_change_to_opening_balance_minor? || will_save_change_to_balance_started_on?
    end

    # An edited opening balance is a new ledger baseline. Anchoring it to the
    # current ledger position keeps older backdated rows from being counted twice,
    # while transactions entered after this save still affect the balance.
    def anchor_balance_basis
      self.balance_anchor_transaction_id = user.transactions.maximum(:id) || 0
    end

    # The opening balance is anchored to both a calendar date and a ledger position.
    # Transactions entered after that position affect the balance even when the user
    # records them with an earlier transaction date. This keeps backdated entries from
    # silently disappearing while preserving historical rows that predate the anchor.
    def balance_activity(scope, as_of:)
      scope.where(transaction_date: ..as_of)
        .where("transactions.transaction_date >= :started_on OR transactions.id > :anchor_id",
          started_on: balance_started_on, anchor_id: balance_anchor_transaction_id)
    end

    def currency_unchanged_after_activity
      return unless will_save_change_to_currency?
      return unless transactions.exists? || incoming_transfers.exists?

      errors.add(:currency, "cannot be changed after the account has transactions")
    end
end
