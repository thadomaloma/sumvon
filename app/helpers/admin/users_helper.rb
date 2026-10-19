module Admin::UsersHelper
  def admin_source_label(user)
    t("admin.role.source_#{user.admin_source}")
  end

  def admin_source_help(user)
    case user.admin_source
    when :environment, :both then t("admin.role.source_environment_help")
    when :database then t("admin.role.source_database_help")
    end
  end

  def account_status_badge(user)
    if user.suspended?
      content_tag :span, t("admin.suspended"), class: "rounded-full bg-rose-50 px-3 py-1 text-xs font-semibold text-rose-700"
    else
      content_tag :span, t("admin.active"), class: "rounded-full bg-brand-tint px-3 py-1 text-xs font-semibold text-brand"
    end
  end
end
