require "test_helper"
require "tempfile"
require "vips"

class Transactions::ReceiptReaderTest < ActiveSupport::TestCase
  setup do
    @photo = Tempfile.new([ "receipt", ".png" ])
    @photo.close
    Vips::Image.black(10, 10).write_to_file(@photo.path)
    @ocr_calls = 0
    @ocr = ->(_photo) { @ocr_calls += 1; "合計 ¥640" }
  end

  teardown { @photo.close! }

  test "uses Claude's reading when it has one" do
    vision_result = Transactions::ReceiptScan::Result.new(amount: BigDecimal("1098"), date: nil, kind: nil)

    result = Transactions::ReceiptReader.new(@photo, vision: ->(_photo) { vision_result }, cloud_ocr: ->(_photo) { flunk "Claude already answered" }, local_ocr: ->(_photo) { flunk "Claude already answered" }, ocr: @ocr).call

    assert_equal BigDecimal("1098"), result.amount
    assert_equal 0, @ocr_calls
  end

  test "reads Cloud Vision text when Claude has no reading" do
    result = Transactions::ReceiptReader.new(@photo, vision: ->(_photo) { nil }, cloud_ocr: ->(_photo) { "合計 ¥1,098" }, local_ocr: ->(_photo) { flunk "Cloud Vision already answered" }, ocr: @ocr).call

    assert_equal BigDecimal("1098"), result.amount
    assert_equal 0, @ocr_calls
  end

  test "reads with RapidOCR when no cloud service is configured" do
    result = Transactions::ReceiptReader.new(@photo, vision: ->(_photo) { nil }, cloud_ocr: ->(_photo) { nil },
      local_ocr: ->(_photo) { "合 計 ¥1.098" }, ocr: @ocr).call

    assert_equal BigDecimal("1098"), result.amount
    assert_equal 0, @ocr_calls
  end

  test "falls back to Tesseract when no other reader has text" do
    result = Transactions::ReceiptReader.new(@photo, vision: ->(_photo) { nil }, cloud_ocr: ->(_photo) { nil },
      local_ocr: ->(_photo) { nil }, ocr: @ocr).call

    assert_equal BigDecimal("640"), result.amount
    assert_equal 1, @ocr_calls
  end

  test "explains that RAW photos can't be scanned" do
    File.binwrite(@photo.path, "II*\x00".b + "\x00".b * 64)

    error = assert_raises(Transactions::ReceiptTextExtractor::ExtractionError) do
      Transactions::ReceiptReader.new(@photo, vision: ->(_photo) { flunk "must not send RAW" }, cloud_ocr: nil, local_ocr: nil, ocr: @ocr).call
    end
    assert_match(/RAW \(ProRAW\/DNG\)/, error.message)
  end

  test "rejects a non-image before sending it anywhere" do
    @photo.open
    @photo.write("plain text")
    @photo.close
    vision = ->(_photo) { flunk "must not send an invalid file to Claude" }

    error = assert_raises(Transactions::ReceiptTextExtractor::ExtractionError) do
      Transactions::ReceiptReader.new(@photo, vision:, cloud_ocr: vision, local_ocr: vision, ocr: @ocr).call
    end
    assert_match(/not a JPEG, PNG, or HEIC/, error.message)
  end
end
