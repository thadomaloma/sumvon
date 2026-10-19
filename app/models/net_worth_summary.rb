class NetWorthSummary
  attr_reader :user, :as_of

  def initialize(user:, as_of: Date.current, accounts: nil)
    @user = user
    @as_of = as_of.to_date
    @accounts = accounts
  end

  def account_rows
    @account_rows ||= accounts.map do |account|
      { account:, balance_minor: balance_for(account), classification: account.liability? ? :liability : :asset }
    end
  end

  def by_currency
    @by_currency ||= account_rows.group_by { |row| row[:account].currency }.transform_values do |rows|
      assets = rows.select { |row| row[:classification] == :asset }.sum { |row| row[:balance_minor] }
      liability_rows = rows.select { |row| row[:classification] == :liability }
      assets += liability_rows.sum { |row| [ row[:balance_minor], 0 ].max }
      liabilities = liability_rows.sum { |row| [ -row[:balance_minor], 0 ].max }
      { assets_minor: assets, liabilities_minor: liabilities, net_worth_minor: assets - liabilities }
    end
  end

  def assets
    account_rows.select { |row| row[:classification] == :asset }
  end

  def liabilities
    account_rows.select { |row| row[:classification] == :liability }
  end

  private
    def accounts
      @accounts ||= user.financial_accounts.ordered.to_a
    end

    def balance_for(account)
      return 0 if as_of < account.balance_started_on

      account.opening_balance_minor + primary_activity.fetch(account.id, 0) + incoming_activity.fetch(account.id, 0) +
        reconciliation_activity.fetch(account.id, 0)
    end

    def primary_activity
      @primary_activity ||= user.transactions.joins(:financial_account).through_date(as_of)
        .where(<<~SQL.squish)
          transactions.transaction_date >= financial_accounts.balance_started_on
          OR transactions.id > financial_accounts.balance_anchor_transaction_id
        SQL
        .group(:financial_account_id).sum(
        Arel.sql("CASE kind WHEN 'income' THEN amount_minor ELSE -amount_minor END")
      )
    end

    def incoming_activity
      @incoming_activity ||= user.transactions.through_date(as_of).transfer.where.not(transfer_account_id: nil)
        .joins("INNER JOIN financial_accounts balance_destinations ON balance_destinations.id = transactions.transfer_account_id")
        .where(<<~SQL.squish)
          transactions.transaction_date >= balance_destinations.balance_started_on
          OR transactions.id > balance_destinations.balance_anchor_transaction_id
        SQL
        .group(:transfer_account_id).sum(:amount_minor)
    end

    def reconciliation_activity
      @reconciliation_activity ||= user.account_reconciliations.joins(:financial_account)
        .where(reconciled_on: ..as_of)
        .where("account_reconciliations.reconciled_on >= financial_accounts.balance_started_on")
        .group(:financial_account_id).sum(:adjustment_minor)
    end
end
