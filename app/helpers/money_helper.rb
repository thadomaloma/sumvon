module MoneyHelper
  CURRENCY_SYMBOLS = {
    "INR" => "₹", "MMK" => "K", "BDT" => "৳", "JPY" => "¥", "KRW" => "₩", "USD" => "$",
    "GBP" => "£", "AUD" => "A$", "CAD" => "C$", "EUR" => "€", "SGD" => "S$", "CNY" => "¥",
    "HKD" => "HK$", "MYR" => "RM", "THB" => "฿", "PHP" => "₱", "NZD" => "NZ$", "CHF" => "CHF "
  }.freeze

  def format_money(minor, currency, show_code: false)
    precision = MoneyAmount.minor_units(currency)
    major = minor.to_d / (10**precision)
    formatted = number_to_currency(major, unit: currency_symbol(currency), precision:, format: "%u%n")
    show_code ? "#{formatted} #{currency}" : formatted
  end

  # Same text as format_money, split into spans so the symbol and minor units can be set
  # quieter than the whole amount. Pass sign: "+"/"−" to force one; negatives get "−".
  def money_tag(minor, currency, sign: nil, show_code: false, **options)
    unit = currency_symbol(currency)
    separator = I18n.t("number.currency.format.separator", default: ".")
    whole, fraction = format_money(minor.abs, currency).delete_prefix(unit).split(separator, 2)
    sign = "−" if sign.nil? && minor.negative?

    parts = []
    parts << tag.span(sign, class: "money-sign") if sign.present?
    parts << tag.span(unit, class: "money-unit")
    parts << whole
    parts << tag.span("#{separator}#{fraction}", class: "money-fraction") if fraction
    parts << tag.span(" #{currency}", class: "money-code") if show_code
    tag.span(safe_join(parts), **options.merge(class: [ "money", options[:class] ]))
  end

  def signed_money_tag(value, currency, **options)
    sign = value.positive? ? "+" : (value.negative? ? "−" : "")
    money_tag(value.abs, currency, sign:, **options)
  end

  # Short axis labels such as ₹83k or ¥1.2M, for charts only.
  def compact_money(minor, currency)
    major = minor.to_d / (10**MoneyAmount.minor_units(currency))
    "#{currency_symbol(currency).strip}#{number_to_human(major, precision: 2, significant: true, format: '%n%u', units: { thousand: 'k', million: 'M', billion: 'B', trillion: 'T' })}"
  end

  def currency_symbol(currency)
    CURRENCY_SYMBOLS.fetch(currency, "#{currency} ")
  end

  def amount_from_minor(minor, currency)
    MoneyAmount.from_minor(minor, currency)
  end
end
