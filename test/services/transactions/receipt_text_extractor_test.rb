require "test_helper"
require "tempfile"
require "vips"

class Transactions::ReceiptTextExtractorTest < ActiveSupport::TestCase
  test "rejects a file without a JPEG or PNG signature" do
    file = Tempfile.new([ "not-a-photo", ".jpg" ])
    file.write("plain text")
    file.rewind

    error = assert_raises(Transactions::ReceiptTextExtractor::ExtractionError) do
      Transactions::ReceiptTextExtractor.call(file)
    end

    assert_match(/not a JPEG, PNG, or HEIC/, error.message)
  ensure
    file&.close!
  end

  test "rejects an oversized receipt before OCR" do
    file = Tempfile.new([ "large-receipt", ".jpg" ])
    file.binmode
    file.write("\xFF\xD8\xFF".b)
    file.truncate(Transactions::ReceiptTextExtractor::MAX_IMAGE_BYTES + 1)
    file.rewind

    error = assert_raises(Transactions::ReceiptTextExtractor::ExtractionError) do
      Transactions::ReceiptTextExtractor.call(file)
    end

    assert_match(/limited to 25 MB/, error.message)
  ensure
    file&.close!
  end

  test "scans the full photo and a focused lower section" do
    file = Tempfile.new([ "receipt", ".png" ])
    file.close
    Vips::Image.black(800, 1_200).write_to_file(file.path)
    calls = []
    extractor = Transactions::ReceiptTextExtractor.new(file)
    ocr = lambda do |path, page_segmentation: nil|
      calls << [ Vips::Image.new_from_file(path).height, page_segmentation ]
      page_segmentation ? "合計 1,250" : "Coffee 800"
    end

    extractor.define_singleton_method(:extract_text, &ocr)
    text = extractor.call

    assert_equal [ [ 1_200, nil ], [ 1_200, 6 ], [ 1_080, 6 ] ], calls
    assert_equal BigDecimal("1250"), Transactions::ReceiptScan.call(text).amount
  ensure
    file&.close!
  end

  test "scans receipt lines when the broader OCR misses the payable total" do
    file = Tempfile.new([ "receipt", ".png" ])
    file.close
    Vips::Image.black(800, 1_200).write_to_file(file.path)
    calls = []
    extractor = Transactions::ReceiptTextExtractor.new(file)
    extractor.define_singleton_method(:extract_text) do |_path, page_segmentation: nil|
      calls << page_segmentation
      page_segmentation == 7 ? "合計 ¥~3. 201" : "小計 ¥2,964\n税合計 ¥237"
    end

    text = extractor.call

    assert_includes calls, 7
    assert_equal BigDecimal("3201"), Transactions::ReceiptScan.call(text).amount
  ensure
    file&.close!
  end

  test "line scan accepts a backslash yen but not a lone item price" do
    file = receipt_image(800, 1_200)
    extractor = Transactions::ReceiptTextExtractor.new(file)
    extractor.define_singleton_method(:extract_text) do |_path, page_segmentation: nil|
      case page_segmentation
      when nil, 6 then "枝豆 \\380\n唐揚げ \\680\nご請求金額"
      else @line_reads = (@line_reads || 0) + 1; @line_reads < 10 ? "唐揚げ \\680" : "ご請求金額 \\4,620"
      end
    end

    text = extractor.call

    assert_equal BigDecimal("4620"), Transactions::ReceiptScan.call(text).amount
  ensure
    file&.close!
  end

  test "skips the line scan when OCR saw no total label" do
    file = receipt_image(800, 1_200)
    calls = []
    extractor = Transactions::ReceiptTextExtractor.new(file)
    extractor.define_singleton_method(:extract_text) do |_path, page_segmentation: nil|
      calls << page_segmentation
      "Coffee 800"
    end

    extractor.call

    assert_equal [ nil, 6, 6 ], calls
  ensure
    file&.close!
  end

  test "shrinks a large photo before OCR" do
    file = receipt_image(4_000, 6_000)
    heights = []
    extractor = Transactions::ReceiptTextExtractor.new(file)
    extractor.define_singleton_method(:extract_text) do |path, page_segmentation: nil|
      heights << Vips::Image.new_from_file(path).height
      "合計 ¥1,250"
    end

    extractor.call

    assert_equal Transactions::ReceiptTextExtractor::MAX_SCAN_EDGE, heights.first
  ensure
    file&.close!
  end

  test "stops running OCR once the scan deadline has passed" do
    extractor = Transactions::ReceiptTextExtractor.new(nil, deadline_seconds: 0)

    error = assert_raises(Transactions::ReceiptTextExtractor::ExtractionError) do
      extractor.send(:extract_text, "unused.png")
    end

    assert_match(/took too long/, error.message)
  end

  test "converts a saved HEIC photo to PNG before OCR" do
    file = Tempfile.new([ "receipt", ".heic" ])
    file.close
    Vips::Image.black(100, 150).write_to_file(file.path)
    scanned_paths = []
    extractor = Transactions::ReceiptTextExtractor.new(file)
    extractor.define_singleton_method(:extract_text) do |path, page_segmentation: nil|
      scanned_paths << path
      page_segmentation ? nil : "合計 ¥1,250"
    end

    text = extractor.call

    assert_equal BigDecimal("1250"), Transactions::ReceiptScan.call(text).amount
    assert scanned_paths.all? { |path| path.end_with?(".png") }
  ensure
    file&.close!
  end

  private
    def receipt_image(width, height)
      file = Tempfile.new([ "receipt", ".png" ])
      file.close
      Vips::Image.black(width, height).write_to_file(file.path)
      file
    end
end
