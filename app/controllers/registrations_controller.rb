class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: t("auth.try_later") }

  def new
    @user = User.new(country_code: "IN", timezone: "Kolkata", default_currency: "INR", locale: "en")
  end

  def create
    @user = User.new(registration_params)
    if @user.save
      start_new_session_for(@user)
      Auditing::Recorder.record("user.registered", actor: @user, subject: @user, request:)
      redirect_to new_financial_account_path, notice: t("auth.welcome")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def registration_params
      params.require(:user).permit(:display_name, :email_address, :password,
        :country_code, :timezone, :default_currency).merge(locale: "en")
    end
end
