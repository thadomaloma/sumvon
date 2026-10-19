require "test_helper"
require "tempfile"

class TransactionImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:two)
    sign_in_as @user
    @account = @user.financial_accounts.create!(name: "Chiba account", account_type: :bank, currency: "JPY")
    @income = Category.find_or_create_by!(name: "Import deposits", kind: :income)
    @expense = Category.find_or_create_by!(name: "Import withdrawals", kind: :expense)
  end

  test "shows Japanese bank import options" do
    get new_transaction_import_path

    assert_response :success
    assert_select "option[value=auto]", text: /auto-detect/
    assert_select "option[value=japan_post]", text: /Japan Post/
    assert_select "option[value=mufg]", text: /MUFG/
    assert_select "option[value=mizuho]", text: /Mizuho/
    assert_select "option[value=chiba_bank]", text: /Chiba Bank/
    assert_select "option[value=smbc]", text: /SMBC/
    assert_select "option[value=chiba_kogyo]", text: /Chiba Kogyo/
    assert_select "input[type=file][accept*='.pdf']"
  end

  test "imports a Chiba Kogyo CSV into the selected account" do
    file = Tempfile.new([ "chiba", ".csv" ])
    file.write("勘定日,摘要,お支払金額,お預り金額,残高\n#{Date.current},コンビニ,500,,99500\n")
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "chiba.csv")
    assert_difference("@user.transactions.count", 1) do
      post transaction_import_path, params: { source_format: "chiba_kogyo", file: upload,
        financial_account_id: @account.id, income_category_id: @income.id, expense_category_id: @expense.id }
    end

    assert_redirected_to transactions_path
    transaction = @user.transactions.last
    assert_equal @account, transaction.financial_account
    assert_equal @expense, transaction.category
    assert_equal 500, transaction.amount_minor
  ensure
    file&.close!
  end
end
