module Authentication
  extend ActiveSupport::Concern

  SESSION_IDLE_TIMEOUT = 14.days
  SESSION_ABSOLUTE_TIMEOUT = 30.days
  SESSION_TOUCH_INTERVAL = 1.hour

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
      return Current.session unless Current.session&.user&.suspended?

      Current.session.destroy
      Current.session = nil
      cookies.delete(:session_id)
      flash[:alert] = t("auth.suspended")
      nil
    end

    def find_session_by_cookie
      return unless cookies.signed[:session_id]

      session_record = Session.find_by(id: cookies.signed[:session_id])
      return unless session_record

      if session_record.created_at < SESSION_ABSOLUTE_TIMEOUT.ago ||
          session_record.updated_at < SESSION_IDLE_TIMEOUT.ago
        session_record.destroy
        cookies.delete(:session_id)
        return
      end

      session_record.touch if session_record.updated_at < SESSION_TOUCH_INTERVAL.ago
      session_record
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.fullpath
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed[:session_id] = {
          value: session.id,
          expires: SESSION_ABSOLUTE_TIMEOUT.from_now,
          httponly: true,
          same_site: :lax,
          secure: Rails.env.production?
        }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
