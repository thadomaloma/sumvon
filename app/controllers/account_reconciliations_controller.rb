class AccountReconciliationsController < ApplicationController
  def create
    account = Current.user.financial_accounts.active.find(reconciliation_params[:financial_account_id])
    reconciliation = account.reconcile!(**reconciliation_params.except(:financial_account_id).to_h.symbolize_keys)
    redirect_to finance_tools_path, notice: t("reconciliations.created", amount: helpers.format_money(reconciliation.adjustment_minor.abs, account.currency))
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid
    redirect_to finance_tools_path, alert: t("reconciliations.invalid")
  end

  private
    def reconciliation_params
      params.require(:account_reconciliation).permit(:financial_account_id, :statement_balance, :reconciled_on, :note)
    end
end
