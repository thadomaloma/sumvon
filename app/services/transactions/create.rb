module Transactions
  class Create
    Result = Data.define(:transaction, :created)

    def self.call(user:, attributes:, source: "web")
      new(user:, attributes:, source:).call
    end

    def initialize(user:, attributes:, source:)
      @user = user
      @attributes = attributes.to_h.symbolize_keys
      @source = source
    end

    def call
      if @attributes[:idempotency_key].present? && (existing = @user.transactions.find_by(idempotency_key: @attributes[:idempotency_key]))
        return Result.new(transaction: existing, created: false)
      end

      transaction = nil
      created = false
      @user.with_lock do
        transaction = @user.transactions.new(base_attributes)
        assign_scoped_references(transaction)
        created = transaction.save
      end
      Result.new(transaction:, created:)
    rescue ActiveRecord::RecordNotUnique
      existing = @user.transactions.find_by!(idempotency_key: @attributes[:idempotency_key])
      Result.new(transaction: existing, created: false)
    end

    private
      def base_attributes
        @attributes.slice(:kind, :amount, :amount_minor, :transaction_date, :description, :idempotency_key).merge(source: @source)
      end

      def assign_scoped_references(transaction)
        transaction.financial_account = @user.financial_accounts.active.find_by(id: @attributes[:financial_account_id])
        transaction.transfer_account = @user.financial_accounts.active.find_by(id: @attributes[:transfer_account_id]) if transaction.transfer?
        transaction.category = @user.available_categories.find_by(id: @attributes[:category_id]) unless transaction.transfer?
      end
  end
end
