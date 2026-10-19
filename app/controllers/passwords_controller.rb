class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: I18n.t("passwords.messages.try_later") }

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
      Auditing::Recorder.record("password.reset_requested", subject: user, request:)
    end

    redirect_to new_session_path, notice: t("passwords.messages.instructions_sent")
  end

  def edit
  end

  def update
    if @user.update(params.permit(:password))
      @user.sessions.destroy_all
      Auditing::Recorder.record("password.changed", subject: @user, request:)
      redirect_to new_session_path, notice: t("passwords.messages.reset_complete")
    else
      redirect_to edit_password_path(params[:token]), alert: t("passwords.messages.mismatch")
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: t("passwords.messages.invalid_link")
    end
end
