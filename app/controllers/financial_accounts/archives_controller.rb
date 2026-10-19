class FinancialAccounts::ArchivesController < ApplicationController
  before_action :set_account

  def create
    @account.update!(archived: true)
    redirect_to financial_accounts_path, notice: t("accounts.archived")
  end

  def destroy
    @account.update!(archived: false)
    redirect_to financial_accounts_path, notice: t("accounts.restored")
  end

  private
    def set_account
      @account = Current.user.financial_accounts.find(params[:financial_account_id])
    end
end
