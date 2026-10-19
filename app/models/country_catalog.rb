class CountryCatalog
  COUNTRIES = [
    [ "IN", "India", "INR" ], [ "MM", "Myanmar", "MMK" ], [ "BD", "Bangladesh", "BDT" ],
    [ "JP", "Japan", "JPY" ], [ "KR", "South Korea", "KRW" ], [ "SG", "Singapore", "SGD" ],
    [ "MY", "Malaysia", "MYR" ], [ "TH", "Thailand", "THB" ], [ "VN", "Vietnam", "VND" ],
    [ "PH", "Philippines", "PHP" ], [ "ID", "Indonesia", "IDR" ], [ "CN", "China", "CNY" ],
    [ "HK", "Hong Kong", "HKD" ], [ "TW", "Taiwan", "TWD" ], [ "NP", "Nepal", "NPR" ],
    [ "BT", "Bhutan", "BTN" ], [ "PK", "Pakistan", "PKR" ], [ "LK", "Sri Lanka", "LKR" ],
    [ "AE", "United Arab Emirates", "AED" ], [ "QA", "Qatar", "QAR" ],
    [ "SA", "Saudi Arabia", "SAR" ], [ "IL", "Israel", "ILS" ], [ "TR", "Türkiye", "TRY" ],
    [ "AU", "Australia", "AUD" ], [ "NZ", "New Zealand", "NZD" ], [ "FJ", "Fiji", "FJD" ],
    [ "GB", "United Kingdom", "GBP" ], [ "IE", "Ireland", "EUR" ], [ "FR", "France", "EUR" ],
    [ "DE", "Germany", "EUR" ], [ "IT", "Italy", "EUR" ], [ "ES", "Spain", "EUR" ],
    [ "PT", "Portugal", "EUR" ], [ "NL", "Netherlands", "EUR" ], [ "BE", "Belgium", "EUR" ],
    [ "AT", "Austria", "EUR" ], [ "FI", "Finland", "EUR" ], [ "GR", "Greece", "EUR" ],
    [ "CH", "Switzerland", "CHF" ], [ "NO", "Norway", "NOK" ], [ "SE", "Sweden", "SEK" ],
    [ "DK", "Denmark", "DKK" ], [ "PL", "Poland", "PLN" ], [ "CZ", "Czechia", "CZK" ],
    [ "HU", "Hungary", "HUF" ], [ "RO", "Romania", "RON" ], [ "UA", "Ukraine", "UAH" ],
    [ "US", "United States", "USD" ], [ "CA", "Canada", "CAD" ], [ "MX", "Mexico", "MXN" ],
    [ "BR", "Brazil", "BRL" ], [ "AR", "Argentina", "ARS" ], [ "CL", "Chile", "CLP" ],
    [ "CO", "Colombia", "COP" ], [ "PE", "Peru", "PEN" ], [ "TT", "Trinidad and Tobago", "TTD" ],
    [ "JM", "Jamaica", "JMD" ], [ "ZA", "South Africa", "ZAR" ], [ "NG", "Nigeria", "NGN" ],
    [ "KE", "Kenya", "KES" ], [ "UG", "Uganda", "UGX" ], [ "TZ", "Tanzania", "TZS" ],
    [ "GH", "Ghana", "GHS" ], [ "EG", "Egypt", "EGP" ], [ "ET", "Ethiopia", "ETB" ],
    [ "BW", "Botswana", "BWP" ], [ "ZM", "Zambia", "ZMW" ], [ "ZW", "Zimbabwe", "USD" ]
  ].freeze

  class << self
    def codes = COUNTRIES.map(&:first).freeze
    def currencies = COUNTRIES.map(&:third).uniq.freeze
    def currency_map = COUNTRIES.to_h { |code, _name, currency| [ code, currency ] }.freeze
    def options = COUNTRIES.map { |code, name, _currency| [ "#{name} (#{code})", code ] }
  end
end
