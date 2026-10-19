class AuditEvent < ApplicationRecord
  SOURCES = %w[web system].freeze
  OUTCOMES = %w[success failure blocked].freeze
  ACTIONS = %w[
    user.registered auth.signed_in auth.sign_in_failed auth.signed_out
    password.reset_requested password.changed admin.access_blocked admin.dashboard_viewed
    admin.users_viewed admin.user_viewed admin.audit_viewed
    admin.user_edit_viewed admin.user_updated admin.role_granted admin.role_revoked
    admin.role_change_blocked admin.user_suspended admin.user_reactivated admin.sessions_revoked
    admin.user_suspension_blocked
    admin.password_reset_initiated admin.user_delete_viewed admin.user_delete_blocked admin.user_deleted
  ].freeze

  belongs_to :actor_user, class_name: "User", optional: true, inverse_of: :audit_events_as_actor
  belongs_to :subject_user, class_name: "User", optional: true, inverse_of: :audit_events_as_subject

  validates :action, inclusion: { in: ACTIONS }
  validates :source, inclusion: { in: SOURCES }
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :request_id, length: { maximum: 64 }, allow_nil: true
  validates :ip_digest, length: { maximum: 32 }, allow_nil: true

  # Admin page views are recorded for accountability but drown out security events when
  # listed together, so overviews can leave them out.
  VIEW_ACTIONS = ACTIONS.select { |action| action.end_with?("_viewed") }.freeze
  ATTENTION_OUTCOMES = %w[failure blocked].freeze
  CATEGORIES = %w[auth password user admin].freeze

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }
  scope :excluding_views, -> { where.not(action: VIEW_ACTIONS) }
  scope :needing_attention, -> { where(outcome: ATTENTION_OUTCOMES) }

  def category = action.split(".").first
  def view? = action.in?(VIEW_ACTIONS)
  def needs_attention? = outcome.in?(ATTENTION_OUTCOMES)
end
