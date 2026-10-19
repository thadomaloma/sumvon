module Admin::AuditHelper
  CATEGORY_ICONS = { "auth" => :lock_closed, "password" => :shield_check, "user" => :user, "admin" => :presentation_chart_line }.freeze

  def audit_action_label(action)
    t("admin.audit.actions.#{action.tr('.', '_')}", default: action.tr(".", " ").humanize)
  end

  def audit_action_options
    AuditEvent::CATEGORIES.map do |category|
      actions = AuditEvent::ACTIONS.select { |action| action.start_with?("#{category}.") }
      [ t("admin.audit.categories.#{category}"), actions.map { |action| [ audit_action_label(action), action ] } ]
    end
  end

  def audit_category_icon(event)
    tone = event.needs_attention? ? "tone-rose" : (event.view? ? "tone-slate" : "tone-#{event.category == 'admin' ? 'indigo' : 'green'}")
    tag.span(heroicon(CATEGORY_ICONS.fetch(event.category, :information_circle), class: "size-4"), class: [ "category-icon category-icon-sm", tone ], aria: { hidden: true })
  end

  # Success is the normal case, so it stays quiet; failures and blocks stand out.
  def audit_outcome_badge(outcome)
    case outcome
    when "failure" then tag.span(t("admin.audit.outcomes.failure"), class: "status-badge status-badge-bad")
    when "blocked" then tag.span(t("admin.audit.outcomes.blocked"), class: "status-badge status-badge-warn")
    else tag.span(t("admin.audit.outcomes.success"), class: "text-xs font-medium text-subtle")
    end
  end

  def audit_metadata_chips(event)
    return if event.metadata.blank?

    safe_join(event.metadata.map { |key, value| tag.span("#{key.to_s.humanize}: #{value}", class: "meta-chip") }, " ")
  end

  def audit_people(event)
    actor = event.actor_user
    subject = event.subject_user
    return tag.span(t("admin.audit.system"), class: "text-subtle") if actor.nil? && subject.nil?
    return safe_join([ audit_user_link(actor), tag.span(" · #{t('admin.audit.self')}", class: "text-subtle") ]) if actor && actor == subject

    parts = [ actor ? audit_user_link(actor) : tag.span(t("admin.audit.system"), class: "text-subtle") ]
    parts += [ tag.span(" → ", class: "text-subtle"), audit_user_link(subject) ] if subject
    safe_join(parts)
  end

  def audit_day_heading(date)
    return t("transactions.today") if date == Date.current
    return t("transactions.yesterday") if date == Date.yesterday

    l(date, format: date.year == Date.current.year ? "%A, %-d %B" : "%A, %-d %B %Y")
  end

  private
    def audit_user_link(user)
      link_to user.display_name, admin_user_path(user), class: "font-medium text-ink hover:text-brand hover:underline"
    end
end
