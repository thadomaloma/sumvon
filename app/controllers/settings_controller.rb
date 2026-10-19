class SettingsController < ApplicationController
  def show
    @user = Current.user
  end

  def update
    @user = Current.user
    if @user.update(settings_params)
      redirect_to settings_path, notice: t("settings.saved")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def settings_params
      params.require(:user).permit(:display_name, :country_code, :timezone, :default_currency)
    end
end
