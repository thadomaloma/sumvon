class FinancialAccountsController < ApplicationController
  before_action :set_account, only: %i[show edit update]

  def index
    @accounts = Current.user.financial_accounts.ordered
    @net_worth = NetWorthSummary.new(user: Current.user)
  end

  def show
    transactions = Current.user.transactions
      .where("financial_account_id = :id OR transfer_account_id = :id", id: @account.id)
      .includes(:financial_account, :transfer_account, :category).recent_first
    @pagy, @transactions = pagy(:offset, transactions, limit: 25)
  end

  def new
    @account = Current.user.financial_accounts.new(currency: Current.user.default_currency,
      balance_started_on: Date.current)
  end

  def create
    @account = Current.user.financial_accounts.new(account_params)
    if @account.save
      redirect_to @account, notice: t("accounts.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @account.update(account_params)
      redirect_to @account, notice: t("accounts.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_account
      @account = Current.user.financial_accounts.find(params[:id])
    end

    def account_params
      params.require(:financial_account).permit(:name, :account_type, :currency, :opening_balance, :balance_started_on)
    end
end
