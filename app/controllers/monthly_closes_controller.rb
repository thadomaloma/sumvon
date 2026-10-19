class MonthlyClosesController < ApplicationController
  def create
    MonthlyClose.close!(user: Current.user, period: Date.strptime(params.require(:monthly_close)[:period], "%Y-%m"))
    redirect_to finance_tools_path, notice: t("monthly_closes.created")
  rescue ActiveRecord::RecordInvalid, Date::Error
    redirect_to finance_tools_path, alert: t("monthly_closes.invalid")
  end

  def destroy
    Current.user.with_lock { Current.user.monthly_closes.find(params[:id]).destroy! }
    redirect_to finance_tools_path, notice: t("monthly_closes.reopened")
  end
end
