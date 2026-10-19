require "test_helper"
require "tempfile"

class Transactions::BankStatementImportTest < ActiveSupport::TestCase
  setup do
    @user = users(:two)
    @account = @user.financial_accounts.create!(name: "SMBC account", account_type: :bank, currency: "JPY")
    @income = Category.find_or_create_by!(name: "Bank deposits", kind: :income)
    @expense = Category.find_or_create_by!(name: "Bank withdrawals", kind: :expense)
  end

  test "imports a Japanese bank CSV idempotently" do
    content = <<~CSV
      日付,お取扱内容,お支払金額,お預り金額,残高
      #{Date.current.iso8601},スーパー,"1,250",,98750
      #{Date.current.iso8601},給与,,"50,000",148750
    CSV
    first_file = uploaded_file(content, "smbc.csv")
    second_file = uploaded_file(content, "renamed.csv")

    first = import(first_file)
    second = import(second_file)

    assert_empty first.errors
    assert_equal 2, first.imported_count
    assert_empty second.errors
    assert_equal 0, second.imported_count
    assert_equal [ 1_250, 50_000 ], @user.transactions.order(:id).last(2).map(&:amount_minor)
    assert @user.transactions.order(:id).last(2).all?(&:import?)
  ensure
    first_file&.close!
    second_file&.close!
  end

  test "does not duplicate a statement when its bank profile changes" do
    content = "取引日,入出金区分,取引内容,取引金額\n#{Date.current},受入,振込,50000\n"
    bank_file = uploaded_file(content, "japan-post.csv")
    auto_file = uploaded_file(content, "japan-post.csv")

    first = Transactions::BankStatementImport.call(user: @user, file: bank_file, bank: "japan_post",
      financial_account_id: @account.id, income_category_id: @income.id, expense_category_id: @expense.id)
    second = Transactions::BankStatementImport.call(user: @user, file: auto_file, bank: "auto",
      financial_account_id: @account.id, income_category_id: @income.id, expense_category_id: @expense.id)

    assert_equal 1, first.imported_count
    assert_equal 0, second.imported_count
    assert_empty second.errors
  ensure
    bank_file&.close!
    auto_file&.close!
  end

  test "rejects another user's account and categories" do
    file = uploaded_file("日付,お取扱内容,お支払金額,お預り金額\n#{Date.current},ATM,1000,\n", "smbc.csv")
    other = users(:one)
    other_account = other.financial_accounts.create!(name: "Private bank", account_type: :bank, currency: "JPY")

    result = Transactions::BankStatementImport.call(user: @user, file:, bank: "smbc",
      financial_account_id: other_account.id, income_category_id: @income.id, expense_category_id: @expense.id)

    assert_equal 0, result.imported_count
    assert_match(/matches this statement/, result.errors.first)
  ensure
    file&.close!
  end

  test "SMBC rejects PDF files" do
    file = uploaded_file("%PDF-fake", "statement.pdf")

    result = import(file)

    assert_equal 0, result.imported_count
    assert_match(/does not support/, result.errors.first)
  ensure
    file&.close!
  end

  private
    def import(file)
      Transactions::BankStatementImport.call(user: @user, file:, bank: "smbc",
        financial_account_id: @account.id, income_category_id: @income.id, expense_category_id: @expense.id)
    end

    def uploaded_file(content, filename)
      Tempfile.new([ "bank-statement", File.extname(filename) ]).tap do |file|
        file.binmode
        file.write(content)
        file.rewind
        file.define_singleton_method(:original_filename) { filename }
      end
    end
end
