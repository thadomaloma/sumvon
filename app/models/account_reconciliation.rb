class AccountReconciliation < ApplicationRecord
  include MoneyAttribute

  belongs_to :user
  belongs_to :financial_account
  delegate :currency, to: :financial_account, allow_nil: true

  money_attribute :statement_balance
  before_validation :calculate_adjustment, if: -> { financial_account && reconciled_on && statement_balance_minor }

  validates :reconciled_on, :statement_balance_minor, :adjustment_minor, presence: true
  validates :statement_balance_minor, :adjustment_minor, numericality: { only_integer: true }
  validates :note, length: { maximum: 240 }
  validate :account_belongs_to_user
  validate :date_is_within_account_ledger
  validate :period_is_open

  private
    # The adjustment is whatever moves the tracked balance onto the bank statement.
    def calculate_adjustment
      self.adjustment_minor = statement_balance_minor - financial_account.current_balance_minor(as_of: reconciled_on)
    end

    def account_belongs_to_user
      errors.add(:financial_account, "is not available") if financial_account && financial_account.user_id != user_id
    end

    def date_is_within_account_ledger
      return unless financial_account && reconciled_on
      errors.add(:reconciled_on, "cannot be before balance tracking starts") if reconciled_on < financial_account.balance_started_on
      errors.add(:reconciled_on, "cannot be in the future") if reconciled_on > Date.current
    end

    def period_is_open
      return unless user && reconciled_on
      errors.add(:reconciled_on, :closed_month) if user.closed_month?(reconciled_on)
    end
end
