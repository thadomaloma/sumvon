class PwaController < ActionController::Base
  skip_forgery_protection only: :service_worker

  def manifest
    expires_in 1.hour, public: true
    render formats: :json, content_type: "application/manifest+json"
  end

  def service_worker
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Service-Worker-Allowed"] = "/"
    render formats: :js, content_type: "application/javascript"
  end
end
