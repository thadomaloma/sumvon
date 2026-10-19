require "pagy"

class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Method
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  around_action :use_user_locale_and_timezone
  after_action :protect_sensitive_html

  private
    def use_user_locale_and_timezone(&block)
      locale = Current.user&.locale
      locale = I18n.default_locale unless locale.in?(User::SUPPORTED_LOCALES)
      timezone = Current.user&.timezone || "UTC"
      I18n.with_locale(locale) { Time.use_zone(timezone, &block) }
    end

    def protect_sensitive_html
      return unless response.media_type == "text/html"
      response.headers["Cache-Control"] = "private, no-store, max-age=0, must-revalidate"
      response.headers["Pragma"] = "no-cache"
      response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
      response.headers["Permissions-Policy"] = "camera=(self), microphone=(), geolocation=(), payment=()"
    end
end
