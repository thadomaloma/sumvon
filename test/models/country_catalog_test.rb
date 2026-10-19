require "test_helper"

class CountryCatalogTest < ActiveSupport::TestCase
  test "offers broad country coverage with country-based currencies" do
    assert_operator CountryCatalog::COUNTRIES.size, :>=, 60
    assert_equal CountryCatalog.codes.uniq, CountryCatalog.codes
    assert_equal "INR", CountryCatalog.currency_map.fetch("IN")
    assert_equal "MMK", CountryCatalog.currency_map.fetch("MM")
    assert_equal "BDT", CountryCatalog.currency_map.fetch("BD")
    assert_equal "USD", CountryCatalog.currency_map.fetch("US")
    assert_equal "EUR", CountryCatalog.currency_map.fetch("DE")
  end

  test "money amounts support added currencies and their minor units" do
    assert_equal 85_000, MoneyAmount.to_minor("850", "MMK")
    assert_equal 85_000, MoneyAmount.to_minor("850", "BDT")
    assert_equal 850, MoneyAmount.to_minor("850", "KRW")
    assert_equal "850", MoneyAmount.from_minor(850, "VND")
  end
end
