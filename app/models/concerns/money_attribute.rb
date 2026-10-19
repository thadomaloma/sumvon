# Lets forms submit decimal amounts ("472.50") while the database stores integer minor
# units. The decimal input is converted in the record's currency right before validation,
# so it doesn't matter whether the currency is assigned before or after the amount.
module MoneyAttribute
  extend ActiveSupport::Concern

  class_methods do
    # money_attribute :amount                 # writes amount_minor
    # money_attribute :opening_balance, minor: :opening_balance_form_minor
    #
    # Pass keep_if_blank: true when a blank input should leave the stored amount untouched.
    def money_attribute(name, minor: :"#{name}_minor", keep_if_blank: false)
      attribute name, :string

      before_validation do
        invalid_money_inputs.delete(name)
        raw = public_send(name)
        next if raw.nil? || (keep_if_blank && raw.blank?)

        converted = MoneyAmount.to_minor(raw, currency)
        public_send(:"#{minor}=", converted)
        invalid_money_inputs << name if raw.present? && converted.nil?
      end

      validate do
        errors.add(name, :invalid_money) if name.in?(invalid_money_inputs)
      end

      # The unparseable input already explains the problem; drop the follow-on
      # "is not a number" noise reported against the stored minor-unit column.
      after_validation do
        errors.delete(:"#{name}_minor") if name.in?(invalid_money_inputs)
      end
    end
  end

  private
    def invalid_money_inputs
      @invalid_money_inputs ||= Set.new
    end
end
