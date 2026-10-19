require "test_helper"
require "csv"
require "tempfile"

class TransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
    @cash = @user.financial_accounts.create!(name: "Cash", account_type: :cash, currency: "INR")
    @bank = @user.financial_accounts.create!(name: "Bank", account_type: :bank, currency: "INR")
    @food = Category.create!(name: "Food controller", kind: :expense)
    @salary = Category.create!(name: "Salary controller", kind: :income)
  end

  test "index uses the desktop header add action without a page-level duplicate" do
    get transactions_path

    assert_response :success
    assert_select "header a[href=?]", new_transaction_path, count: 1
    assert_select "main > div a[href=?].md\\:inline-flex", new_transaction_path, count: 0
    assert_select "details[data-filter-layout='mobile'].md\\:hidden", count: 1
    assert_select "form.hidden.md\\:grid", count: 1
    assert_select "details[data-filter-layout='mobile'] [data-controller='month-filter']", count: 1
    assert_select "#mobile-filter-month-part[name]", count: 0
    assert_select "#mobile-filter-year-part[name]", count: 0
    assert_select "#mobile-filter-month", count: 0
    assert_select "#desktop-filter-month[type='month']", count: 1
  end

  test "mobile month filter preserves the selected month and offers relevant years" do
    @user.transactions.create!(kind: :expense, amount_minor: 500, financial_account: @cash,
      category: @food, currency: "INR", transaction_date: Date.new(2024, 3, 15))

    get transactions_path, params: { month: "2024-03" }

    assert_response :success
    assert_select "details[data-filter-layout='mobile'] input[name='month'][value='2024-03']", count: 1
    assert_select "#mobile-filter-month-part option[value='03'][selected]", text: "March"
    assert_select "#mobile-filter-year-part option[value='2024'][selected]", text: "2024"
    assert_select "#mobile-filter-year-part option[value='#{Date.current.year}']", count: 1
  end

  test "transaction links leave the paginated turbo frame for the detail page" do
    transaction = @user.transactions.create!(kind: :expense, amount_minor: 500, financial_account: @cash,
      category: @food, currency: "INR", transaction_date: Date.current)

    get transactions_path

    assert_select "turbo-frame#transaction-list a[href='#{transaction_path(transaction)}'][data-turbo-frame='_top']", count: 1
  end

  test "account filter includes incoming transfers to the selected destination" do
    transfer = @user.transactions.create!(kind: :transfer, amount_minor: 500, financial_account: @cash,
      transfer_account: @bank, currency: "INR", transaction_date: Date.current, description: "Incoming destination")

    get transactions_path, params: { account_id: @bank.id }

    assert_response :success
    assert_select "a[href='#{transaction_path(transfer)}']", count: 1
  end

  test "index presents export links that preserve current filters" do
    get transactions_path, params: { month: "2026-08", kind: "expense", account_id: @cash.id, category_id: @food.id }

    assert_select "form[action=?][data-turbo-frame]", transactions_path, count: 0
    link = css_select("a").find { |node| node["href"].to_s.start_with?("/transactions.csv") }
    uri = URI.parse(link["href"])
    query = Rack::Utils.parse_nested_query(uri.query)
    assert_equal "/transactions.csv", uri.path
    assert_equal({ "month" => "2026-08", "kind" => "expense", "account_id" => @cash.id.to_s,
      "category_id" => @food.id.to_s }, query)
    assert_select "details[data-filter-layout='mobile']", text: /4 active/
    assert_select "details[data-filter-layout='mobile'] a[href=?]", transactions_path, text: "Clear"

    statement_link = css_select("a").find { |node| node["href"].to_s.start_with?("/transactions/statement") }
    statement_uri = URI.parse(statement_link["href"])
    assert_equal "/transactions/statement", statement_uri.path
    assert_equal query, Rack::Utils.parse_nested_query(statement_uri.query)
  end

  test "index paginates transactions and preserves filters in page links" do
    26.times do |index|
      @user.transactions.create!(kind: :expense, amount_minor: 100 + index, financial_account: @cash,
        category: @food, currency: "INR", transaction_date: Date.current, description: "Page item #{index}")
    end

    get transactions_path, params: { kind: "expense" }

    assert_response :success
    assert_select "#transaction-list .divide-y > a", count: 25
    assert_select "[data-pagination]", count: 1
    next_link = css_select("[data-pagination] a[rel='next']").first
    next_query = Rack::Utils.parse_nested_query(URI.parse(next_link["href"]).query)
    assert_equal "2", next_query["page"]
    assert_equal "expense", next_query["kind"]

    get transactions_path, params: { kind: "expense", page: 2 }

    assert_response :success
    assert_select "#transaction-list .divide-y > a", count: 1
    assert_select "[data-pagination]", text: /Showing 26–26 of 26/
  end

  test "account activity paginates instead of truncating transaction history" do
    26.times do |index|
      @user.transactions.create!(kind: :expense, amount_minor: 100 + index, financial_account: @cash,
        category: @food, currency: "INR", transaction_date: Date.current)
    end

    get financial_account_path(@cash, page: 2)

    assert_response :success
    assert_select ".panel .divide-y > a", count: 1
    assert_select "[data-pagination]", text: /Page 2 of 2/
  end

  test "exports filtered user-scoped UTF-8 CSV without internal identifiers" do
    special_account = @user.financial_accounts.create!(name: "=Formula Bank", account_type: :bank, currency: "INR")
    exported = @user.transactions.create!(kind: :expense, amount_minor: 1_250, financial_account: special_account,
      category: @food, currency: "INR", transaction_date: Date.new(2026, 8, 12), description: "  =2+2")
    @user.transactions.create!(kind: :income, amount_minor: 9_900, financial_account: special_account,
      category: @salary, currency: "INR", transaction_date: exported.transaction_date, description: "not exported")
    other_user = users(:two)
    other_account = other_user.financial_accounts.create!(name: "Other secret bank", account_type: :bank, currency: "INR")
    other_category = Category.create!(name: "Other secret category", kind: :expense, user: other_user)
    other_user.transactions.create!(kind: :expense, amount_minor: 5_000, financial_account: other_account,
      category: other_category, currency: "INR", transaction_date: exported.transaction_date, description: "other-user-secret")

    get transactions_path(format: :csv), params: { month: "2026-08", kind: "expense", account_id: special_account.id }

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/attachment; filename="sumvon-transactions-2026-08.csv"/, response.headers["Content-Disposition"])
    assert_match(/private/, response.headers["Cache-Control"])
    assert_match(/no-store/, response.headers["Cache-Control"])
    assert response.body.start_with?("\uFEFF")
    rows = CSV.parse(response.body.delete_prefix("\uFEFF"), headers: true)
    assert_equal Transactions::CsvExport::HEADERS, rows.headers
    assert_equal 1, rows.length
    assert_equal "12.50", rows.first["Amount"]
    assert_equal "'=Formula Bank", rows.first["Account"]
    assert_equal "'  =2+2", rows.first["Description"]
    assert_no_match(/other-user-secret|user_id|idempotency/i, response.body)
  end

  test "invalid export month does not raise and uses a dated filename" do
    get transactions_path(format: :csv), params: { month: "2026-99" }

    assert_response :success
    assert_match(/sumvon-transactions-#{Date.current.iso8601}\.csv/, response.headers["Content-Disposition"])
  end

  test "renders a filtered user-scoped A4 transaction statement" do
    included = @user.transactions.create!(kind: :expense, amount_minor: 1_250, financial_account: @cash,
      category: @food, currency: "INR", transaction_date: Date.new(2026, 8, 12), description: "Market")
    @user.transactions.create!(kind: :income, amount_minor: 9_900, financial_account: @bank,
      category: @salary, currency: "INR", transaction_date: included.transaction_date)
    other_user = users(:two)
    other_account = other_user.financial_accounts.create!(name: "Private bank", account_type: :bank, currency: "INR")
    other_category = Category.create!(name: "Private category", kind: :expense, user: other_user)
    other_user.transactions.create!(kind: :expense, amount_minor: 5_000, financial_account: other_account,
      category: other_category, currency: "INR", transaction_date: included.transaction_date, description: "Private item")

    get transactions_statement_path, params: { month: "2026-08", kind: "expense", account_id: @cash.id }

    assert_response :success
    assert_select "h1", "August 2026"
    assert_select ".statement-sheet"
    assert_select ".statement-table tbody tr", count: 1
    assert_select ".statement-table", text: /Market/
    assert_select ".statement-currency-summary", text: /₹12\.50/
    assert_select "body", text: /Private item/, count: 0
    assert_select "header.app-header", count: 0
  end

  test "the statement flags transactions dated after today and explains they are not in balances yet" do
    travel_to Date.new(2026, 8, 10) do
      @user.transactions.create!(kind: :expense, amount_minor: 2_000_000, financial_account: @bank,
        category: @food, currency: "INR", transaction_date: Date.new(2026, 8, 20), description: "Rent")
      @user.transactions.create!(kind: :income, amount_minor: 500_000, financial_account: @bank,
        category: @salary, currency: "INR", transaction_date: Date.new(2026, 8, 5))

      get transactions_statement_path, params: { month: "2026-08" }

      assert_select ".statement-upcoming-note", text: "Includes 1 transaction dated after today (₹20,000.00 in expenses). Account balances only count it from that date."
      assert_select ".statement-table tbody tr", count: 2
      assert_select ".statement-upcoming-tag", count: 1, text: "Upcoming"
    end
  end

  test "the statement charts spending by category next to the totals, folding small categories into Other" do
    names = %w[Rent Food Travel Phone Gifts Books]
    names.each_with_index do |name, index|
      category = Category.create!(name: "#{name} breakdown", kind: :expense)
      @user.transactions.create!(kind: :expense, amount_minor: (6 - index) * 1_000, financial_account: @cash,
        category:, currency: "INR", transaction_date: Date.current)
    end
    @user.transactions.create!(kind: :income, amount_minor: 50_000, financial_account: @bank,
      category: @salary, currency: "INR", transaction_date: Date.current)

    get transactions_statement_path

    assert_select ".statement-currency-row .statement-breakdown[data-breakdown-kind=expense]" do
      assert_select "figcaption", text: /Spending by category · INR/
      assert_select "li", count: 5
      assert_select "li:first-child .statement-breakdown-name", text: "Rent breakdown"
      assert_select "li:first-child .statement-breakdown-value", text: /₹60\.00\s+29%/
      assert_select "li.is-other .statement-breakdown-name", text: "2 other categories"
      assert_select "li.is-other .statement-breakdown-value", text: /₹30\.00/
    end
  end

  test "an income-only statement charts income by category and a transfer-only one has no chart" do
    @user.transactions.create!(kind: :income, amount_minor: 9_900, financial_account: @bank,
      category: @salary, currency: "INR", transaction_date: Date.current)

    get transactions_statement_path, params: { kind: "income" }
    assert_select ".statement-breakdown[data-breakdown-kind=income] figcaption", text: /Income by category/

    @user.transactions.delete_all
    @user.transactions.create!(kind: :transfer, amount_minor: 1_000, financial_account: @cash,
      transfer_account: @bank, currency: "INR", transaction_date: Date.current)
    get transactions_statement_path
    assert_select ".statement-breakdown", count: 0
  end

  test "the statement has no upcoming note when nothing is dated after today" do
    @user.transactions.create!(kind: :expense, amount_minor: 1_000, financial_account: @cash,
      category: @food, currency: "INR", transaction_date: Date.current)

    get transactions_statement_path

    assert_select ".statement-upcoming-note", count: 0
    assert_select ".statement-upcoming-tag", count: 0
  end

  test "the transaction list marks rows dated after today as upcoming" do
    @user.transactions.create!(kind: :expense, amount_minor: 1_000, financial_account: @cash,
      category: @food, currency: "INR", transaction_date: Date.current.next_day)
    @user.transactions.create!(kind: :expense, amount_minor: 1_000, financial_account: @cash,
      category: @food, currency: "INR", transaction_date: Date.current)

    get transactions_path

    assert_select "#transaction-list .upcoming-badge", count: 1, text: "Upcoming"
  end

  test "creates an expense from a major-unit form amount" do
    assert_difference("@user.transactions.count") do
      post transactions_path, params: { transaction: { kind: "expense", amount: "12.50", financial_account_id: @cash.id,
        category_id: @food.id, transaction_date: Date.current } }
    end
    assert_equal 1_250, @user.transactions.last.amount_minor
  end

  test "creates a transaction only once when an idempotency key is retried" do
    key = SecureRandom.uuid
    transaction_params = { transaction: { kind: "expense", amount: "12.50", financial_account_id: @cash.id,
      category_id: @food.id, transaction_date: Date.current, idempotency_key: key } }

    assert_difference("@user.transactions.count", 1) do
      post transactions_path, params: transaction_params
    end

    saved_transaction = @user.transactions.find_by!(idempotency_key: key)
    assert_no_difference("@user.transactions.count") do
      post transactions_path, params: transaction_params
    end
    assert_redirected_to transaction_path(saved_transaction)
    assert_equal I18n.t("transactions.already_saved"), flash[:notice]
  end

  test "retains an idempotency key when validation fails" do
    key = SecureRandom.uuid

    assert_no_difference("@user.transactions.count") do
      post transactions_path, params: { transaction: { kind: "expense", amount: "12.50",
        financial_account_id: @cash.id, transaction_date: Date.current, idempotency_key: key } }
    end

    assert_response :unprocessable_entity
    assert_select "input[name='transaction[idempotency_key]'][value='#{key}']"
  end

  test "allows different users to use the same idempotency key" do
    key = SecureRandom.uuid
    @user.transactions.create!(kind: :expense, amount_minor: 500, financial_account: @cash,
      category: @food, currency: "INR", transaction_date: Date.current, idempotency_key: key)
    other_user = users(:two)
    other_account = other_user.financial_accounts.create!(name: "Other cash", account_type: :cash, currency: "INR")
    other_category = Category.create!(name: "Other food", kind: :expense, user: other_user)

    assert other_user.transactions.create!(kind: :expense, amount_minor: 500, financial_account: other_account,
      category: other_category, currency: "INR", transaction_date: Date.current, idempotency_key: key)
  end

  test "rejects fractional minor units and out-of-range amounts without an error page" do
    [ "1.999", "1e100" ].each do |amount|
      assert_no_difference("@user.transactions.count") do
        post transactions_path, params: { transaction: { kind: "expense", amount: amount,
          financial_account_id: @cash.id, category_id: @food.id, transaction_date: Date.current } }
      end
      assert_response :unprocessable_entity
    end
  end

  test "creates a transfer as one record" do
    assert_difference("@user.transactions.count") do
      post transactions_path, params: { transaction: { kind: "transfer", amount: "30", financial_account_id: @cash.id,
        transfer_account_id: @bank.id, transaction_date: Date.current } }
    end
    assert @user.transactions.last.transfer?
    assert_equal 3_000, @bank.current_balance_minor
  end

  test "edits a transaction and recalculates balance" do
    transaction = @user.transactions.create!(kind: :expense, amount_minor: 500, financial_account: @cash,
      category: @food, currency: "INR", transaction_date: Date.current)
    patch transaction_path(transaction), params: { transaction: { kind: "expense", amount: "7", financial_account_id: @cash.id,
      category_id: @food.id, transaction_date: Date.current } }
    assert_equal 700, transaction.reload.amount_minor
    assert_equal(-700, @cash.current_balance_minor)
  end

  test "edit form still offers a transaction's account after it is archived" do
    transaction = @user.transactions.create!(kind: :expense, amount_minor: 500, financial_account: @cash,
      category: @food, currency: "INR", transaction_date: Date.current)
    @cash.update!(archived: true)

    get edit_transaction_path(transaction)

    assert_response :success
    assert_select "select#transaction_financial_account_id option[value=?]", @cash.id.to_s
  end

  test "saving an edited transaction keeps its archived account instead of silently swapping it" do
    transaction = @user.transactions.create!(kind: :expense, amount_minor: 500, financial_account: @cash,
      category: @food, currency: "INR", transaction_date: Date.current)
    @cash.update!(archived: true)

    patch transaction_path(transaction), params: { transaction: { kind: "expense", amount: "7",
      financial_account_id: @cash.id, category_id: @food.id, transaction_date: Date.current, description: "Updated" } }

    assert_equal @cash, transaction.reload.financial_account
    assert_equal "Updated", transaction.description
  end

  test "receipt form offers camera capture and saved photo upload" do
    get new_transaction_path

    assert_response :success
    assert_select "input[type='file'][capture='environment'][data-action='change->receipt-scan#scan']", count: 1
    assert_select "input[type='file'][accept='image/jpeg,image/png,image/heic,image/heif,.heic,.heif']:not([capture])", count: 1
    assert_select "form[data-receipt-scan-url-value=?]", transactions_receipt_scan_path
  end

  test "scan_receipt rejects a photo that is not a JPEG PNG or HEIC" do
    file = Tempfile.new([ "not-a-photo", ".jpg" ])
    file.write("plain text")
    file.rewind
    upload = Rack::Test::UploadedFile.new(file.path, "image/jpeg", original_filename: "receipt.jpg")

    post transactions_receipt_scan_path, params: { photo: upload }

    assert_response :unprocessable_entity
    assert_match(/not a JPEG, PNG, or HEIC/, JSON.parse(response.body)["error"])
  ensure
    file&.close!
  end

  test "scan_receipt requires a photo" do
    post transactions_receipt_scan_path

    assert_response :unprocessable_entity
    assert_match(/Choose a receipt photo/, JSON.parse(response.body)["error"])
  end
end
