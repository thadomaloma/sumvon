module Admin
  class AuditEventsController < BaseController
    PERIODS = [ 1, 7, 30, 90 ].freeze

    def index
      scope = AuditEvent.includes(:actor_user, :subject_user).recent_first
      # `params[:action]` is always the controller action in Rails, so the event filter
      # needs its own name.
      scope = scope.where(action: params[:event]) if params[:event].in?(AuditEvent::ACTIONS)
      scope = scope.where(source: params[:source]) if params[:source].in?(AuditEvent::SOURCES)
      scope = filter_outcome(scope)
      scope = scope.where(created_at: params[:period].to_i.days.ago..) if params[:period].to_i.in?(PERIODS)
      scope = scope.excluding_views if params[:hide_views] == "1"
      if params[:user_id].present?
        user_id = params[:user_id].to_i
        scope = scope.where(actor_user_id: user_id).or(scope.where(subject_user_id: user_id))
      end
      @active_filters = params.permit(:event, :source, :outcome, :period, :hide_views, :user_id).to_h.compact_blank
      @pagy, @audit_events = pagy(scope, limit: 40)
      audit_admin_view("audit")
    end

    private
      def filter_outcome(scope)
        return scope.needing_attention if params[:outcome] == "attention"
        return scope.where(outcome: params[:outcome]) if params[:outcome].in?(AuditEvent::OUTCOMES)

        scope
      end
  end
end
