class TransactionImportsController < ApplicationController
  before_action :load_collections

  def new; end

  def create
    result = if params[:source_format] == "sumvon"
      Transactions::CsvImport.call(user: Current.user, file: params[:file])
    else
      Transactions::BankStatementImport.call(user: Current.user, file: params[:file], bank: params[:source_format],
        financial_account_id: params[:financial_account_id], income_category_id: params[:income_category_id],
        expense_category_id: params[:expense_category_id])
    end
    if result.errors.any?
      @errors = result.errors
      @imported_count = result.imported_count
      render :new, status: :unprocessable_entity
    else
      redirect_to transactions_path, notice: t("imports.created", count: result.imported_count)
    end
  end

  private
    def load_collections
      @accounts = Current.user.financial_accounts.active.ordered
      @income_categories = Current.user.available_categories(:income).ordered
      @expense_categories = Current.user.available_categories(:expense).ordered
    end
end
