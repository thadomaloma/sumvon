# The month, kind, account, and category filters shared by the transaction list,
# its CSV export, and the printable statement.
module TransactionFiltering
  extend ActiveSupport::Concern

  private
    def filtered_transactions
      scope = Current.user.transactions
      scope = scope.where(kind: params[:kind]) if params[:kind].in?(Transaction::USER_SELECTABLE_KINDS)
      if params[:account_id].present?
        scope = scope.where("financial_account_id = :account_id OR transfer_account_id = :account_id",
          account_id: params[:account_id])
      end
      scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?
      scope = scope.in_month(parsed_month) if parsed_month
      scope
    end

    def parsed_month
      return unless /\A\d{4}-\d{2}\z/.match?(params[:month].to_s)
      Date.strptime(params[:month], "%Y-%m")
    rescue Date::Error
      nil
    end
end
