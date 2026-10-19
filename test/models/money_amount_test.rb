require "test_helper"

class MoneyAmountTest < ActiveSupport::TestCase
  test "zero-decimal currencies like JPY have no minor unit precision" do
    assert_equal 0, MoneyAmount.minor_units("JPY")
    assert_equal 82_000, MoneyAmount.to_minor("82000", "JPY")
    assert_equal "82000", MoneyAmount.from_minor(82_000, "JPY")
  end

  test "decimal currencies like INR and USD use two minor units" do
    assert_equal 2, MoneyAmount.minor_units("INR")
    assert_equal 2, MoneyAmount.minor_units("USD")
    assert_equal 47_250, MoneyAmount.to_minor("472.50", "INR")
    assert_equal "472.50", MoneyAmount.from_minor(47_250, "INR")
  end

  test "conversion never introduces floating-point drift" do
    # 0.1 + 0.2 style errors are the classic float trap; BigDecimal must avoid them.
    100.times do |cents|
      amount = "#{cents}.10"
      minor = MoneyAmount.to_minor(amount, "USD")
      assert_equal (cents * 100) + 10, minor
    end
  end

  test "rejects unsupported currencies and unparsable amounts" do
    assert_nil MoneyAmount.to_minor("100", "XXX")
    assert_nil MoneyAmount.to_minor("not-a-number", "INR")
    assert_nil MoneyAmount.to_minor("", "INR")
    assert_nil MoneyAmount.to_minor("1.5", "JPY")
    assert_nil MoneyAmount.to_minor("1.999", "INR")
    assert_nil MoneyAmount.to_minor("NaN", "INR")
    assert_nil MoneyAmount.to_minor("1e100", "INR")
  end
end
