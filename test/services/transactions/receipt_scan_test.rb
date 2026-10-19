require "test_helper"

class Transactions::ReceiptScanTest < ActiveSupport::TestCase
  test "finds the total amount and a slash-formatted date" do
    result = Transactions::ReceiptScan.call(<<~TEXT)
      Sunshine Cafe
      2026/09/12
      Coffee          450
      Sandwich        800
      合計           1,250
    TEXT

    assert_equal BigDecimal("1250"), result.amount
    assert_equal Date.new(2026, 9, 12), result.date
  end

  test "reads a Japanese date that OCR spaced out" do
    result = Transactions::ReceiptScan.call(<<~TEXT)
      2026 年 10 月 3 日
      小計 \\1.000
      合計 ¥1,080
    TEXT

    assert_equal BigDecimal("1080"), result.amount
    assert_equal Date.new(2026, 10, 3), result.date
  end

  test "serializes form-ready values" do
    assert_equal({ amount: "1080", date: "2026-10-03", kind: nil, alternatives: [] },
      Transactions::ReceiptScan::Result.new(amount: BigDecimal("1080"), date: Date.new(2026, 10, 3), kind: nil).as_json)
    assert_equal({ amount: "12.5", date: nil, kind: "transfer", alternatives: [ "386215" ] },
      Transactions::ReceiptScan::Result.new(amount: BigDecimal("12.50"), date: nil, kind: "transfer",
        alternatives: [ BigDecimal("386215") ]).as_json)
  end

  test "reads a Japanese era date" do
    result = Transactions::ReceiptScan.call(<<~TEXT)
      令和8年9月12日
      お会計 ¥3,600
    TEXT

    assert_equal BigDecimal("3600"), result.amount
    assert_equal Date.new(2026, 9, 12), result.date
  end

  test "does not guess an amount from item prices without a total" do
    result = Transactions::ReceiptScan.call(<<~TEXT)
      Item A 300
      Item B 900
      Item C 150
    TEXT

    assert_nil result.amount
  end

  test "uses the amount instead of an item count on a total line" do
    result = Transactions::ReceiptScan.call("合計 3点 ￥1,250")

    assert_equal BigDecimal("1250"), result.amount
  end

  test "reads a total printed on the next line" do
    result = Transactions::ReceiptScan.call("合 計\n¥1,280\nお預り ¥2,000\nお釣り ¥720")

    assert_equal BigDecimal("1280"), result.amount
  end

  test "prefers the final payable total to an earlier subtotal" do
    result = Transactions::ReceiptScan.call("小計 ¥980\n消費税 ¥98\n合計 ¥1,078\nお支払金額 ¥1,078\nポイント残高 2000")

    assert_equal BigDecimal("1078"), result.amount
  end

  test "ignores a tax total and reads OCR-spaced yen thousands" do
    result = Transactions::ReceiptScan.call("(税合計 ¥237)\n合計 ¥~3. 201\nお預り ¥5,001\nお釣り ¥1,800")

    assert_equal BigDecimal("3201"), result.amount
  end

  test "does not mistake a tax total for the payable amount" do
    result = Transactions::ReceiptScan.call("外税計 ¥237\n(税合計 ¥237)")

    assert_nil result.amount
  end

  test "ignores dates and counts beside a total label" do
    result = Transactions::ReceiptScan.call("2026/09/25 合計点数 3\n合計 3点 2026/09/25 1,250")

    assert_equal BigDecimal("1250"), result.amount
  end

  test "does not use a total item count as the amount" do
    result = Transactions::ReceiptScan.call("合計 3点\nカード残高 5000")

    assert_nil result.amount
  end

  test "reads a dot-formatted date" do
    result = Transactions::ReceiptScan.call("2026.09.12\n合計 800")

    assert_equal Date.new(2026, 9, 12), result.date
  end

  test "returns nils when nothing recognizable is present" do
    result = Transactions::ReceiptScan.call("garbled unreadable text")

    assert_nil result.amount
    assert_nil result.date
  end

  # The samples below are Tesseract output from photographed receipts, misreads included.
  test "supermarket: misread total label agrees with cash paid and ignores the discount total" do
    result = Transactions::ReceiptScan.call(<<~'TEXT')
      2026 年 10 月 3 日 ( 土 ) 18:42 レジ 02
      バナナ \198
      小計 ¥2,188
      外 税 8% \175
      値 引 合計 -50
      Gat ¥2,354
      台 計 点数 7点
      お 預り ¥5,000
      お 釣り \2.646
      ポイ ント 残高 320pt
      有効 期限 2027 年 3 月 31 日
    TEXT

    assert_equal BigDecimal("2354"), result.amount
    assert_equal Date.new(2026, 10, 3), result.date
    assert_nil result.kind
  end

  test "convenience store: misread 合計 matches the IC card payment" do
    result = Transactions::ReceiptScan.call(<<~'TEXT')
      2026 年 10 月 04 日 (日 ) 07:58
      小計 ( 税 抜 8%) \454
      消費 税 等 (8%) ¥36
      吾 計 \648
      (税率 8% 対 象 \490)
      交通 系 IC \648
      お 釣 ¥0
      残高 \1.234
    TEXT

    assert_equal BigDecimal("648"), result.amount
  end

  test "drugstore: a misread total digit is outvoted by the card payment and subtotal plus tax" do
    result = Transactions::ReceiptScan.call(<<~'TEXT')
      26-09-30 19:12
      小計 \2.974
      消費 税 \304
      お 買上 げ 合 計  \3,27g
      クレ シッ ト ¥3,278
    TEXT

    assert_equal BigDecimal("3278"), result.amount
    assert_equal Date.new(2026, 9, 30), result.date
  end

  test "card slip: reads the charged amount" do
    result = Transactions::ReceiptScan.call(<<~'TEXT')
      ご 利用 控え
      ご 利用 日 2026/09/27
      支払 区 分 一 括
      ご 利用 金額 ¥12,800
    TEXT

    assert_equal BigDecimal("12800"), result.amount
    assert_equal Date.new(2026, 9, 27), result.date
  end

  test "ATM withdrawal: reads the withdrawn amount, not the fee or balance, as a transfer" do
    result = Transactions::ReceiptScan.call(<<~'TEXT')
      セブン 銀行
      お 引出 し
      R08.10.03 14:05
      金額 20,000 円
      手数料 110 円
      残高 123,456 円
    TEXT

    assert_equal BigDecimal("20000"), result.amount
    assert_equal Date.new(2026, 10, 3), result.date
    assert_equal "transfer", result.kind
  end

  test "ATM withdrawal: recovers a 円 that OCR read as a trailing digit" do
    result = Transactions::ReceiptScan.call(<<~'TEXT')
      ゆう ちょ 銀行
      取扱 日 R8.9.25 11:47
      お 取引 内 容 お 引出 し
      お 引出 金額 50,0004
      料金 0 円
      現在 高 812.345 円
    TEXT

    assert_equal BigDecimal("50000"), result.amount
    assert_equal Date.new(2026, 9, 25), result.date
    assert_equal "transfer", result.kind
  end

  test "ATM deposit is also a transfer" do
    result = Transactions::ReceiptScan.call(<<~'TEXT')
      ○○ 銀行 ATM
      2026/09/30 15:02
      お 預入 れ
      お 預入 金額 ¥100,000
      お 取引 後 残高 ¥345,678
    TEXT

    assert_equal BigDecimal("100000"), result.amount
    assert_equal "transfer", result.kind
  end

  test "a store receipt mentioning a point balance is not a bank slip" do
    assert_nil Transactions::ReceiptScan.call("合計 ¥500\nWAON残高 ¥3,210").kind
  end

  test "falls back to the only price shown when every label was misread" do
    result = Transactions::ReceiptScan.call(<<~'TEXT')
      CAFE A
      カー ド 会 社 VI'SA
      =Fi\Fee  ¥12,800
    TEXT

    assert_equal BigDecimal("12800"), result.amount
  end

  test "subtotal plus tax alone never becomes the amount" do
    result = Transactions::ReceiptScan.call(<<~'TEXT')
      小計 ¥3,840
      サービス料 ¥360
      消費税 ¥420
    TEXT

    assert_nil result.amount
  end

  test "an unreadable change amount does not turn the cash handed over into the total" do
    result = Transactions::ReceiptScan.call(<<~'TEXT')
      明言 十 ¥1,098
      お 預 り ¥1.100
      お 釣
    TEXT

    assert_equal BigDecimal("1098"), result.amount
  end

  test "offers the printed amounts instead of guessing when every label was lost" do
    result = Transactions::ReceiptScan.call(<<~'TEXT')
      ma 0 OU ロ ¥200, 000 上 RN 4
      0456 ¥386, 215 Sy
      ご 利用 手数 料 \110 y
    TEXT

    assert_nil result.amount
    assert_equal [ BigDecimal("200000"), BigDecimal("386215") ], result.alternatives.sort
  end

  test "offers the total first when its label was lost, because receipts repeat it" do
    result = Transactions::ReceiptScan.call(<<~'TEXT')
      部 大 盛 ね ぎ 塩焼 そば \599※
      良 味 コー ンス ナッ ク \118※
      良 味 チー ズ ス ナッ ク \118※
      aS st ¥1, 098
      (内 税 8. OOK RAR ¥1, 098)
      へ お 買上 明細 は 、 上 記 の 通り で す 。
      ies ¥1,098
    TEXT

    assert_nil result.amount
    assert_equal BigDecimal("1098"), result.alternatives.first
  end

  test "the receipt footer お買上明細 is not a total label" do
    assert_not Transactions::ReceiptScan::PAYABLE_LABEL.match?("お買上明細は、上記の通りです。")
    assert Transactions::ReceiptScan::PAYABLE_LABEL.match?("お買上げ合計")
  end

  test "takes the first amount on an ATM slip whose labels were lost, offering the rest" do
    result = Transactions::ReceiptScan.call(<<~'TEXT')
      キ ャ ッ シ ュ サ ー ビ ス ご 利 用 明 細
      n ち ば 興 銀
      4 嘉0 I U 0 そ ⑳0, 000
      國 80456 ¥386, 215
      ー 利 用 手 数 料 \① ①0
    TEXT

    assert_equal BigDecimal("200000"), result.amount
    assert_equal [ BigDecimal("386215") ], result.alternatives
    assert_equal "transfer", result.kind
  end

  test "a bank transfer payment slip is not a transfer between own accounts" do
    assert_nil Transactions::ReceiptScan.call("○○銀行 ATM\nお振込\nお取引金額 ¥30,000").kind
  end

  test "stray ATM letters in OCR noise do not make a store receipt a bank slip" do
    assert_nil Transactions::ReceiptScan.call("ATM fe 合計 ¥1,312\nお預り ¥2,000\nお釣り ¥688").kind
  end

  test "offers runners-up only when a single clue chose the amount" do
    weak = Transactions::ReceiptScan.call("明言 十 ¥1,098\nPayPay 支払 ¥1,100")
    strong = Transactions::ReceiptScan.call("合計 ¥1,098\nお預り ¥1,100\nお釣 ¥2")

    assert_equal [ BigDecimal("1098"), BigDecimal("1100") ], [ weak.amount, *weak.alternatives ].sort
    assert_equal BigDecimal("1098"), strong.amount
    assert_empty strong.alternatives
  end

  test "ignores a sub-¥10 total that is OCR noise" do
    assert_equal BigDecimal("1098"), Transactions::ReceiptScan.call("aS 言 二 \\1 。 OB8\n明言 十 ¥1,098").amount
  end

  test "reads a date whose year OCR lost" do
    result = Transactions::ReceiptScan.call("| や す ①0 月 ④ 日 ( 日 ) ⑨:④⑦\n合計 ¥500")
    expected = Date.new(Date.current.year, 10, 4)
    expected = expected.prev_year if expected > Date.current + 1

    assert_equal expected, result.date
  end

  test "reads labels that PaddleOCR printed in simplified kanji" do
    result = Transactions::ReceiptScan.call("○○銀行\nお取引金额\n¥30,000\nご利用手数料 ¥110")

    assert_equal BigDecimal("30000"), result.amount
    assert_equal "transfer", result.kind
  end

  test "skips expiry and future dates" do
    result = Transactions::ReceiptScan.call(<<~TEXT)
      有効期限 2027年3月31日
      #{Date.current.next_year.strftime("%Y/%m/%d")}
      #{Date.current.strftime("%Y年%m月%d日")}
      合計 ¥500
    TEXT

    assert_equal Date.current, result.date
  end
end
