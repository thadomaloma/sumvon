class BudgetsController < ApplicationController
  before_action :set_budget, only: %i[show edit update destroy]

  def index
    @month = parsed_month(params[:month])
    @budgets = Current.user.budgets.for_period(@month).includes(budget_categories: :category).order(:currency)
    @summaries = @budgets.map { |budget| BudgetSummary.new(budget) }
  end

  def show
    @summary = BudgetSummary.new(@budget)
    @performance = BudgetPerformance.new(budget: @budget).call
  end

  def new
    month = parsed_month(params[:month])
    @budget = Current.user.budgets.new(year: month.year, month: month.month, currency: params[:currency] || Current.user.default_currency)
    source = Current.user.budgets.includes(:budget_categories).find_by(id: params[:copy_from]) if params[:copy_from].present?
    @budget.copy_plan_from(source) if source
  end

  def create
    @budget = Current.user.budgets.new(budget_params)
    if @budget.save
      redirect_to @budget, notice: t("budgets.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @budget.update(budget_params)
      redirect_to @budget, notice: t("budgets.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    month = @budget.reporting_month
    @budget.destroy!
    redirect_to budgets_path(month: month.strftime("%Y-%m")), notice: t("budgets.deleted"), status: :see_other
  end

  private
    def set_budget
      @budget = Current.user.budgets.find(params[:id])
    end

    def budget_params
      params.require(:budget).permit(:year, :month, :reporting_month, :currency, :planned_amount, :rollover_enabled, allocations: {})
    end

    def parsed_month(value)
      value.present? ? Date.strptime(value, "%Y-%m").beginning_of_month : Date.current.beginning_of_month
    rescue Date::Error
      Date.current.beginning_of_month
    end
end
