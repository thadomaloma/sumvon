require "test_helper"

class Transactions::JapanBankStatementParserTest < ActiveSupport::TestCase
  test "parses SMBC deposit and withdrawal columns" do
    entries = Transactions::JapanBankStatementParser.from_csv(<<~CSV)
      日付,お取扱内容,お支払金額,お預り金額,残高
      2026/09/01,給与,,,300000
      2026/09/02,スーパー,"1,250",,298750
      2026/09/03,振込入金,,"50,000",348750
    CSV

    assert_equal 2, entries.size
    assert_equal [ :expense, :income ], entries.map(&:kind)
    assert_equal [ "1250.0", "50000.0" ], entries.map(&:amount)
    assert_equal [ "スーパー", "振込入金" ], entries.map(&:description)
  end

  test "parses Windows-31J Chiba Kogyo CSV after metadata rows" do
    csv = <<~CSV
      ちば興銀入出金明細
      勘定日,摘要,お支払金額,お預り金額,残高
      2026年9月1日,電気料金,"8,000",,92000
      2026年9月2日,振込,,"20,000",112000
    CSV

    entries = Transactions::JapanBankStatementParser.from_csv(csv.encode(Encoding::Windows_31J))

    assert_equal [ Date.new(2026, 9, 1), Date.new(2026, 9, 2) ], entries.map(&:date)
    assert_equal [ :expense, :income ], entries.map(&:kind)
  end

  test "parses Japan Post deposit and withdrawal codes with combined details" do
    entries = Transactions::JapanBankStatementParser.from_csv(<<~CSV, bank: "japan_post")
      取引日,入出金区分,取引内容,送金人名等,取引金額,現在（貸付）高,EDI情報等
      2026/09/01,受入,振込,ヤマダ タロウ,50000,150000,INV-42
      2026/09/02,払出,料金払込,デンキ,8000,142000,
    CSV

    assert_equal [ :income, :expense ], entries.map(&:kind)
    assert_equal [ "振込 · ヤマダ タロウ · INV-42", "料金払込 · デンキ" ], entries.map(&:description)
  end

  test "parses MUFG business codes and compact Japanese-era dates" do
    entries = Transactions::JapanBankStatementParser.from_csv(<<~CSV, bank: "mufg")
      取引日,入払区分,取引区分,取引金額,振込依頼人名,摘要
      080901,1,11,25000,ABC CO,売上
      080902,2,10,5000,,ATM
    CSV

    assert_equal [ Date.new(2026, 9, 1), Date.new(2026, 9, 2) ], entries.map(&:date)
    assert_equal [ :income, :expense ], entries.map(&:kind)
    assert_equal [ "ABC CO · 売上", "ATM" ], entries.map(&:description)
  end

  test "parses common Mizuho split amount columns" do
    entries = Transactions::JapanBankStatementParser.from_csv(<<~CSV, bank: "mizuho")
      お取引日,摘要,お引出し額,お預入れ額,残高
      2026-09-01,カード,1200,,98800
      2026-09-02,振込,,20000,118800
    CSV

    assert_equal [ :expense, :income ], entries.map(&:kind)
  end

  test "parses Chiba Bank date and CRDT DBIT codes" do
    entries = Transactions::JapanBankStatementParser.from_csv(<<~CSV, bank: "chiba_bank")
      預入・払出日,入払区分,取引金額,摘要
      080901,CRDT,30000,振込入金
      080902,DBIT,4000,口座振替
    CSV

    assert_equal [ Date.new(2026, 9, 1), Date.new(2026, 9, 2) ], entries.map(&:date)
    assert_equal [ :income, :expense ], entries.map(&:kind)
  end

  test "auto-detects another Japanese bank using generic columns" do
    entries = Transactions::JapanBankStatementParser.from_csv(<<~CSV)
      年月日,内容,出金金額,入金金額,取引後残高
      20260901,買い物,900,,99100
    CSV

    assert_equal :expense, entries.first.kind
    assert_equal "買い物", entries.first.description
  end

  test "treats zero in an unused amount column as blank" do
    entries = Transactions::JapanBankStatementParser.from_csv(<<~CSV)
      取引日,取引内容,出金額,入金額,残高
      2026/09/01,ATM,10000,0,90000
      2026/09/02,振込,0,25000,115000
    CSV

    assert_equal [ :expense, :income ], entries.map(&:kind)
    assert_equal [ "10000.0", "25000.0" ], entries.map(&:amount)
  end

  test "parses a text-based Chiba Kogyo PDF table" do
    row = ->(date, description, withdrawal, deposit, balance) do
      [ date.ljust(11), description.ljust(22), withdrawal.ljust(11), deposit.ljust(11), balance ].join
    end
    text = [ "入出金明細", row.call("勘定日", "摘要", "お支払金額", "お預り金額", "残高"),
      row.call("2026/09/01", "電気料金", "8,000", "", "92,000"),
      row.call("2026/09/02", "振込", "", "20,000", "112,000") ].join("\n")

    entries = Transactions::JapanBankStatementParser.from_pdf_text(text)

    assert_equal 2, entries.size
    assert_equal [ :expense, :income ], entries.map(&:kind)
    assert_equal [ "8000.0", "20000.0" ], entries.map(&:amount)
  end

  test "rejects unrecognized statements" do
    error = assert_raises(Transactions::JapanBankStatementParser::ParseError) do
      Transactions::JapanBankStatementParser.from_csv("unknown,columns\n1,2\n")
    end

    assert_match(/could not be recognized/, error.message)
  end
end
