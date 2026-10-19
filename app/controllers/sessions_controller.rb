class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: I18n.t("auth.try_later") }

  def new
    redirect_to root_path if authenticated?
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      if user.suspended?
        Auditing::Recorder.record("auth.sign_in_failed", subject: user, outcome: "blocked", request:)
        redirect_to new_session_path, alert: t("auth.suspended")
      else
        start_new_session_for user
        Auditing::Recorder.record("auth.signed_in", actor: user, subject: user, request:)
        redirect_to after_authentication_url
      end
    else
      Auditing::Recorder.record("auth.sign_in_failed", outcome: "failure", request:)
      # Re-render so the email stays filled in; only the password has to be typed again.
      flash.now[:alert] = t("auth.invalid_credentials")
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    user = Current.user
    terminate_session
    Auditing::Recorder.record("auth.signed_out", actor: user, subject: user, request:)
    redirect_to new_session_path, status: :see_other
  end
end
