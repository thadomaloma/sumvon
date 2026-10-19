class TransactionsController < ApplicationController
  include TransactionFiltering

  before_action :set_transaction, only: %i[show edit update destroy]
  before_action :load_form_collections, only: %i[new create edit update]

  def index
    transactions = filtered_transactions.includes(:financial_account, :transfer_account, :category).recent_first

    respond_to do |format|
      format.html do
        @pagy, @transactions = pagy(:offset, transactions, limit: 25)
        @accounts = Current.user.financial_accounts.ordered
        @categories = Current.user.available_categories.ordered
        @filter_years = transaction_filter_years
      end
      format.csv { export_csv(transactions) }
    end
  end

  def show; end

  def new
    @transaction = Current.user.transactions.new(
      kind: params[:kind].presence_in(Transaction::USER_SELECTABLE_KINDS) || "expense",
      transaction_date: Date.current,
      financial_account: @accounts.first,
      currency: @accounts.first&.currency || Current.user.default_currency
    )
    @transaction.idempotency_key = SecureRandom.uuid
  end

  def create
    result = Transactions::Create.call(user: Current.user, attributes: transaction_params)
    @transaction = result.transaction
    if @transaction.persisted?
      redirect_to(result.created ? transactions_path : @transaction,
        notice: t(result.created ? "transactions.created" : "transactions.already_saved"))
    elsif closed_period_rejected?
      render_closed_period
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if Current.user.with_lock { @transaction.update(transaction_params.except(:idempotency_key)) }
      redirect_to transactions_path, notice: t("transactions.updated")
    elsif closed_period_rejected?
      render_closed_period
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if Current.user.with_lock { @transaction.destroy }
      redirect_to transactions_path, notice: t("transactions.deleted"), status: :see_other
    else
      redirect_to @transaction, alert: t("monthly_closes.locked")
    end
  end

  private
    # Historical rows from retired modules remain preserved but are not part of the active
    # transaction ledger and cannot be edited through generic endpoints.
    def set_transaction
      @transaction = Current.user.transactions.find(params[:id])
    end

    def load_form_collections
      @accounts = Current.user.financial_accounts.active.ordered
      if @transaction&.persisted?
        @accounts |= [ @transaction.financial_account, @transaction.transfer_account ].compact
      end
      @categories = Current.user.available_categories.ordered
    end

    def transaction_params
      params.require(:transaction).permit(:kind, :amount, :financial_account_id, :transfer_account_id,
        :category_id, :transaction_date, :description, :idempotency_key)
    end

    def closed_period_rejected?
      @transaction.errors.of_kind?(:transaction_date, :closed_month)
    end

    def render_closed_period
      redirect_to transactions_path, alert: t("monthly_closes.locked")
    end

    def export_csv(transactions)
      response.headers["Cache-Control"] = "private, no-store, max-age=0, must-revalidate"
      response.headers["Pragma"] = "no-cache"
      period = parsed_month&.strftime("%Y-%m") || Time.zone.today.iso8601
      send_data Transactions::CsvExport.generate(transactions),
        filename: "sumvon-transactions-#{period}.csv",
        type: "text/csv; charset=utf-8",
        disposition: "attachment"
    end

    def transaction_filter_years
      years = [ Date.current.year, parsed_month&.year,
        Current.user.transactions.minimum(:transaction_date)&.year,
        Current.user.transactions.maximum(:transaction_date)&.year ].compact
      (years.min..years.max).to_a.reverse
    end
end
