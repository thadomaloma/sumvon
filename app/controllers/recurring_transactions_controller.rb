class RecurringTransactionsController < ApplicationController
  def create
    recurring = Current.user.recurring_transactions.new(recurring_params.except(:financial_account_id, :transfer_account_id, :category_id))
    recurring.financial_account = Current.user.financial_accounts.active.find_by(id: recurring_params[:financial_account_id])
    recurring.transfer_account = Current.user.financial_accounts.active.find_by(id: recurring_params[:transfer_account_id])
    recurring.category = Current.user.available_categories.find_by(id: recurring_params[:category_id])

    if recurring.save
      redirect_to finance_tools_path, notice: t("recurring.created")
    else
      redirect_to finance_tools_path, alert: recurring.errors.full_messages.to_sentence
    end
  end

  def destroy
    Current.user.recurring_transactions.find(params[:id]).destroy!
    redirect_to finance_tools_path, notice: t("recurring.deleted")
  end

  private
    def recurring_params
      params.require(:recurring_transaction).permit(:kind, :amount, :financial_account_id, :transfer_account_id,
        :category_id, :frequency, :next_on, :description)
    end
end
