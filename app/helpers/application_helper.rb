module ApplicationHelper
  def country_options
    CountryCatalog.options
  end

  def currency_options
    MoneyAmount::CURRENCIES
  end

  def nav_link(label, path, icon: nil)
    active = current_page?(path)
    link_to path, class: [ "sidebar-link", ("is-active" if active) ], aria: { current: (active ? "page" : nil) } do
      safe_join([ (heroicon(icon, variant: active ? :solid : :outline, class: "size-5 shrink-0") if icon), content_tag(:span, label) ].compact)
    end
  end

  def mobile_nav_link(icon, label, path)
    active = current_page?(path)
    link_to path, class: [ "mobile-nav-link", ("is-active" if active) ], aria: { current: (active ? "page" : nil) } do
      safe_join([ heroicon(icon, variant: active ? :solid : :outline, class: "size-6"), content_tag(:span, label) ])
    end
  end

  def transaction_sign(transaction, account: nil)
    return "+" if transaction.income?
    return "−" if transaction.expense?
    account && transaction.transfer_account_id == account.id ? "+" : "−"
  end

  def transaction_date_heading(date)
    return t("transactions.today") if date == Date.current
    return t("transactions.yesterday") if date == Date.yesterday

    l(date, format: date.year == Date.current.year ? "%A, %-d %B" : "%A, %-d %B %Y")
  end

  # "₹1,000.00 in income and ₹30,500.00 in expenses", leaving out whichever is zero.
  def upcoming_amounts(income_minor, expense_minor, currency)
    parts = []
    parts << t("transactions.upcoming_income", amount: format_money(income_minor, currency)) if income_minor.positive?
    parts << t("transactions.upcoming_expenses", amount: format_money(expense_minor, currency)) if expense_minor.positive?
    parts.to_sentence(two_words_connector: " #{t('transactions.and')} ", last_word_connector: " #{t('transactions.and')} ")
  end

  def progress_width(percentage)
    percentage.to_f.clamp(0, 100)
  end

  def budget_status_label(status)
    t("budgets.statuses.#{status}")
  end

  # Month-over-month change as a percentage chip. Rising income or savings is good;
  # rising spending is not, so good_when flips the colour for expenses.
  def delta_badge(difference, previous, good_when: :up)
    return if previous.nil? || previous.zero? || difference.nil?

    percentage = (difference.to_d / previous.abs * 100).round
    tone = if percentage.zero? then "delta-neutral"
    elsif (percentage.positive? && good_when == :up) || (percentage.negative? && good_when == :down) then "delta-good"
    else "delta-bad"
    end
    arrow = percentage.negative? ? "↓" : (percentage.positive? ? "↑" : "")
    tag.span("#{arrow}#{percentage.abs}%", class: [ "delta", tone ])
  end

  def difference_label(value, currency)
    sign = value.positive? ? "+" : (value.negative? ? "−" : "")
    "#{sign}#{format_money(value.abs, currency)}"
  end
end
