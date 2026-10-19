module CategoryHelper
  # Default categories get a recognisable icon and tone; custom ones fall back to a tone
  # derived from the name so the same category always looks the same.
  CATEGORY_VISUALS = {
    "Food & Groceries" => [ :shopping_cart, "amber" ],
    "Dining" => [ :building_storefront, "orange" ],
    "Housing" => [ :home_modern, "indigo" ],
    "Transport" => [ :truck, "sky" ],
    "Utilities" => [ :bolt, "yellow" ],
    "Shopping" => [ :shopping_bag, "pink" ],
    "Health" => [ :heart, "rose" ],
    "Education" => [ :academic_cap, "violet" ],
    "Family Support" => [ :users, "teal" ],
    "Entertainment" => [ :film, "purple" ],
    "Travel" => [ :globe_alt, "cyan" ],
    "Personal" => [ :user, "slate" ],
    "Donations" => [ :gift, "rose" ],
    "Other" => [ :tag, "slate" ],
    "Salary" => [ :briefcase, "green" ],
    "Business" => [ :building_storefront, "green" ],
    "Freelance" => [ :briefcase, "teal" ],
    "Allowance" => [ :wallet, "green" ],
    "Pension" => [ :building_library, "green" ],
    "Gift" => [ :gift, "green" ],
    "Refund" => [ :receipt_refund, "green" ],
    "Other Income" => [ :banknotes, "green" ]
  }.freeze
  FALLBACK_TONES = %w[amber indigo sky teal violet pink cyan orange].freeze

  def category_icon_tag(category, transfer: false, size: :md)
    name = category.respond_to?(:name) ? category.name : category
    icon, tone =
      if transfer
        [ :arrows_right_left, "slate" ]
      elsif category.nil?
        [ :tag, "slate" ]
      else
        CATEGORY_VISUALS.fetch(name) { [ nil, FALLBACK_TONES[name.sum % FALLBACK_TONES.size] ] }
      end

    content = icon ? heroicon(icon, class: size == :sm ? "size-4" : "size-5") : name.first.upcase
    tag.span(content, class: [ "category-icon", "tone-#{tone}", "category-icon-#{size}" ], aria: { hidden: true })
  end

  ACCOUNT_VISUALS = {
    "cash" => [ :banknotes, "green" ],
    "bank" => [ :building_library, "indigo" ],
    "savings" => [ :currency_dollar, "amber" ],
    "e_wallet" => [ :wallet, "sky" ],
    "credit_card" => [ :credit_card, "rose" ],
    "other" => [ :squares_2x2, "slate" ]
  }.freeze

  def account_icon_tag(account, size: :md)
    icon, tone = ACCOUNT_VISUALS.fetch(account.account_type, [ :wallet, "slate" ])
    tag.span(heroicon(icon, class: size == :sm ? "size-4" : "size-5"), class: [ "category-icon", "tone-#{tone}", "category-icon-#{size}" ], aria: { hidden: true })
  end
end
