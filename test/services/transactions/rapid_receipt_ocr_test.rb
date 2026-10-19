require "test_helper"
require "tempfile"
require "vips"

class Transactions::RapidReceiptOcrTest < ActiveSupport::TestCase
  setup do
    @photo = Tempfile.new([ "receipt", ".jpg" ])
    @photo.close
    Vips::Image.black(3_000, 4_000).write_to_file(@photo.path)
  end

  teardown { @photo.close! }

  test "rebuilds rows from RapidOCR's text lines so labels sit beside their amounts" do
    # RapidOCR returns spaced-out labels and their amounts as separate boxes.
    text = ocr_with([
      [ "2026年10月4日（日）9:47", 100, 200 ],
      [ "合", 100, 300 ], [ "計", 300, 300 ], [ "¥1.098", 900, 302 ],
      [ "(内税 8.00%対象额", 100, 380 ], [ "¥1,098)", 900, 380 ],
      [ "お預り", 100, 460 ], [ "¥1.100", 900, 460 ],
      [ "お", 100, 540 ], [ "釣", 300, 540 ], [ "¥2", 950, 540 ]
    ]).call

    assert_includes text, "合 計 ¥1.098"
    result = Transactions::ReceiptScan.call(text)
    assert_equal BigDecimal("1098"), result.amount
    assert_equal Date.new(2026, 10, 4), result.date
    assert_empty result.alternatives
  end

  test "reads an ATM slip whose amount sits under its label" do
    text = ocr_with([
      [ "キャッシュサービスご利用明細票", 100, 100 ],
      [ "お取引種别", 100, 200 ], [ "お取扱日", 520, 200 ],
      [ "支払", 100, 280 ], [ "08-10-04 340 52", 520, 280 ],
      [ "口座番号", 900, 360 ],
      [ "お取引紙幣枚数", 100, 440 ], [ "お取引金额", 900, 440 ],
      [ "2000", 100, 520 ], [ "¥200,000", 1_050, 520 ],
      [ "お取引後残高（頭部一印はご融資残高）", 600, 600 ],
      [ "0456", 150, 680 ], [ "¥386,215", 1_050, 680 ],
      [ "ご利用手数料", 650, 760 ], [ "¥110", 1_100, 760 ]
    ]).call

    result = Transactions::ReceiptScan.call(text)
    assert_equal BigDecimal("200000"), result.amount
    assert_equal Date.new(2026, 10, 4), result.date
    assert_equal "transfer", result.kind
  end

  test "sends RapidOCR a shrunken JPEG without metadata" do
    sent = nil
    Transactions::RapidReceiptOcr.new(@photo, runner: ->(path) { sent = Vips::Image.new_from_file(path); "[]" }).call

    assert_equal Transactions::RapidReceiptOcr::MAX_EDGE, sent.height
    assert_empty sent.get_fields.grep(/exif|gps/i)
  end

  test "returns nil so Tesseract can try when RapidOCR finds nothing or fails" do
    assert_nil Transactions::RapidReceiptOcr.new(@photo, runner: ->(_path) { "[]" }).call
    assert_nil Transactions::RapidReceiptOcr.new(@photo, runner: ->(_path) { "not json" }).call
    failing = ->(_path) { raise Transactions::RapidReceiptOcr::ReadError, "RapidOCR failed" }
    assert_nil Transactions::RapidReceiptOcr.new(@photo, runner: failing).call
  end

  test "is off unless RECEIPT_OCR_PYTHON names an executable" do
    original = ENV["RECEIPT_OCR_PYTHON"]
    ENV["RECEIPT_OCR_PYTHON"] = "/nonexistent/python"
    assert_not Transactions::RapidReceiptOcr.enabled?
    ENV.delete("RECEIPT_OCR_PYTHON")
    assert_nil Transactions::RapidReceiptOcr.call(@photo)
  ensure
    ENV["RECEIPT_OCR_PYTHON"] = original
  end

  # Runs the real Python script when RapidOCR is installed (the Docker image, or a
  # developer's virtualenv); CI doesn't install it.
  test "reads a rendered receipt with the real RapidOCR" do
    skip "RapidOCR is not installed (set RECEIPT_OCR_PYTHON)" unless Transactions::RapidReceiptOcr.enabled?

    file = Tempfile.new([ "rendered", ".png" ])
    file.close
    text = Vips::Image.text("2026年10月4日\n小計 ¥1,000\n合計 ¥1,080\nお預り ¥2,000\nお釣 ¥920", dpi: 300)
    ((text > 128).ifthenelse(0, 255).cast(:uchar)).embed(80, 80, text.width + 160, text.height + 160, extend: :white).write_to_file(file.path)

    result = Transactions::ReceiptScan.call(Transactions::RapidReceiptOcr.call(file))

    assert_equal BigDecimal("1080"), result.amount
    assert_equal Date.new(2026, 10, 4), result.date
  ensure
    file&.close!
  end

  private
    def ocr_with(lines)
      json = lines.map do |text, left, top|
        right = left + text.length * 40
        { text:, box: [ [ left, top ], [ right, top ], [ right, top + 40 ], [ left, top + 40 ] ], score: 0.95 }
      end.to_json
      Transactions::RapidReceiptOcr.new(@photo, runner: ->(_path) { json })
    end
end
