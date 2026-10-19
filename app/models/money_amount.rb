class MoneyAmount
  MAX_MINOR = (2**63) - 1
  CURRENCIES = CountryCatalog.currencies
  ZERO_DECIMAL_CURRENCIES = %w[CLP JPY KRW UGX VND].freeze

  def self.minor_units(currency)
    ZERO_DECIMAL_CURRENCIES.include?(currency) ? 0 : 2
  end

  def self.to_minor(amount, currency)
    return unless currency.in?(CURRENCIES)
    precision = minor_units(currency)
    decimal = BigDecimal(amount.to_s)
    scaled = decimal * (10**precision)
    return unless decimal.finite? && scaled.frac.zero? && scaled.abs <= MAX_MINOR

    scaled.to_i
  rescue ArgumentError, FloatDomainError
    nil
  end

  def self.from_minor(minor, currency)
    precision = minor_units(currency)
    format("%.#{precision}f", minor.to_d / (10**precision))
  end
end
