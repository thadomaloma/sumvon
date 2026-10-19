expense_categories = [
  "Food & Groceries", "Dining", "Housing", "Transport", "Utilities", "Shopping", "Health",
  "Education", "Family Support", "Entertainment", "Travel", "Personal", "Donations", "Other"
]
income_categories = [ "Salary", "Business", "Freelance", "Allowance", "Pension", "Gift", "Refund", "Other Income" ]

{ expense: expense_categories, income: income_categories }.each do |kind, names|
  names.each_with_index do |name, position|
    Category.find_or_create_by!(user: nil, kind:, name:) { |category| category.position = position }
  end
end

if Rails.env.development? && ENV["DEMO_DATA"] == "1"
  demo_balance_started_on = Date.current.beginning_of_month.prev_month(5)
  user = User.find_or_create_by!(email_address: "demo@sumvon.local") do |record|
    record.assign_attributes(display_name: "Demo User", password: "demo-password", password_confirmation: "demo-password",
      country_code: "IN", timezone: "Kolkata", default_currency: "INR", locale: "en")
  end
  cash = user.financial_accounts.find_or_initialize_by(name: "Cash").tap { |account| account.update!(account_type: :cash, currency: "INR", opening_balance_minor: 50_000, balance_started_on: demo_balance_started_on) }
  bank = user.financial_accounts.find_or_initialize_by(name: "Main Bank").tap { |account| account.update!(account_type: :bank, currency: "INR", opening_balance_minor: 2_500_000, balance_started_on: demo_balance_started_on) }
  card = user.financial_accounts.find_or_initialize_by(name: "Credit Card").tap { |account| account.update!(account_type: :credit_card, currency: "INR", opening_balance_minor: -120_000, balance_started_on: demo_balance_started_on) }
  user.financial_accounts.find_or_initialize_by(name: "Japan Savings").tap { |account| account.update!(account_type: :savings, currency: "JPY", opening_balance_minor: 150_000, balance_started_on: demo_balance_started_on) }
  salary = Category.find_by!(kind: :income, name: "Salary")
  food = Category.find_by!(kind: :expense, name: "Food & Groceries")
  housing = Category.find_by!(kind: :expense, name: "Housing")
  transport = Category.find_by!(kind: :expense, name: "Transport")

  6.times do |offset|
    month = Date.current.beginning_of_month.prev_month(offset)
    income_amount = 7_800_000 + (5 - offset) * 100_000
    food_amount = 700_000 + offset * 45_000
    user.transactions.find_or_initialize_by(description: "Demo salary #{month}").tap do |transaction|
      transaction.update!(kind: :income, amount_minor: income_amount, financial_account: bank,
        category: salary, currency: "INR", transaction_date: month + 1.day)
    end
    [ [ food, food_amount, cash, "groceries" ], [ housing, 2_000_000, bank, "rent" ], [ transport, 350_000 + offset * 20_000, card, "transport" ] ].each do |category, amount, account, label|
      user.transactions.find_or_initialize_by(description: "Demo #{label} #{month}").tap do |transaction|
        transaction.update!(kind: :expense, amount_minor: amount, financial_account: account,
          category:, currency: "INR", transaction_date: month + 6.days)
      end
    end

    budget = user.budgets.find_or_initialize_by(year: month.year, month: month.month, currency: "INR")
    budget.planned_amount_minor = 4_000_000
    budget.save!
    { food => 1_000_000, housing => 2_200_000, transport => 300_000 }.each do |category, amount|
      budget.budget_categories.find_or_initialize_by(category:).update!(planned_amount_minor: amount)
    end
  end
end
