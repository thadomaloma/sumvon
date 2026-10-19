require "test_helper"
require "tempfile"
require "vips"

class Transactions::CloudReceiptOcrTest < ActiveSupport::TestCase
  setup do
    @photo = Tempfile.new([ "receipt", ".jpg" ])
    @photo.close
    Vips::Image.black(3_000, 4_000).write_to_file(@photo.path)
    @original_key = ENV["GOOGLE_VISION_API_KEY"]
    ENV["GOOGLE_VISION_API_KEY"] = "test-key"
  end

  teardown do
    @photo.close!
    ENV["GOOGLE_VISION_API_KEY"] = @original_key
  end

  test "rebuilds printed rows from a tilted photo so labels sit beside their amounts" do
    # A store receipt whose blocks come back in column order, photographed 4° off level.
    annotation = vision_response([
      [ [ "2026年10月", 100 ], [ "4日(日)", 420 ], [ "9:47", 640 ] ],
      [ [ "合", 100 ], [ "計", 300 ], [ "¥1,098", 900 ] ],
      [ [ "お", 100 ], [ "預", 200 ], [ "り", 300 ], [ "¥1,100", 900 ] ],
      [ [ "お", 100 ], [ "釣", 250 ], [ "¥2", 950 ] ]
    ], tilt_degrees: 4, full_text: "合計\nお預り\nお釣\n¥1,098\n¥1,100\n¥2")

    text = ocr_with(annotation).call

    assert_includes text, "合 計 ¥1,098"
    result = Transactions::ReceiptScan.call(text)
    assert_equal BigDecimal("1098"), result.amount
    assert_equal Date.new(2026, 10, 4), result.date
  end

  test "reads a Chiba Kogyo Bank ATM withdrawal slip" do
    annotation = vision_response([
      [ [ "お取引種別", 100 ], [ "お取扱日", 520 ] ],
      [ [ "支", 100 ], [ "払", 300 ], [ "08-10-04", 520 ], [ "340", 1_100 ], [ "52", 1_300 ] ],
      [ [ "口座番号", 900 ] ],
      [ [ "お取引紙幣枚数", 100 ], [ "お取引金額", 900 ], [ "円", 1_350 ] ],
      [ [ "20", 100 ], [ "0", 400 ], [ "¥200,000", 1_050 ] ],
      [ [ "お取引後残高", 600 ], [ "円", 1_350 ] ],
      [ [ "0456", 150 ], [ "¥386,215", 1_050 ] ],
      [ [ "ご利用手数料", 650 ], [ "¥110", 1_100 ] ]
    ])

    result = Transactions::ReceiptScan.call(ocr_with(annotation).call)

    assert_equal BigDecimal("200000"), result.amount
    assert_equal Date.new(2026, 10, 4), result.date
    assert_equal "transfer", result.kind
  end

  test "sends a metadata-free JPEG with the key in a header, not the URL" do
    sent = nil
    Transactions::CloudReceiptOcr.new(@photo, http: ->(request) { sent = request; ok({ responses: [ {} ] }) }).call

    assert_equal "test-key", sent["X-Goog-Api-Key"]
    assert_not_includes sent.path, "key"
    image = JSON.parse(sent.body).dig("requests", 0, "image", "content")
    sent_image = Vips::Image.new_from_buffer(Base64.decode64(image), "")
    assert_equal Transactions::CloudReceiptOcr::MAX_EDGE, sent_image.height
    assert_empty sent_image.get_fields.grep(/exif|gps/i)
  end

  test "returns nil so Tesseract can try when the service fails" do
    assert_nil ocr_with({ responses: [ { error: { message: "API key not valid" } } ] }).call
    assert_nil Transactions::CloudReceiptOcr.new(@photo, http: ->(_request) { Net::HTTPForbidden.new("1.1", "403", "Forbidden") }).call
    assert_nil Transactions::CloudReceiptOcr.new(@photo, http: ->(_request) { raise Net::ReadTimeout }).call
    assert_nil ocr_with({ responses: [ {} ] }).call
  end

  test "is off without an API key" do
    ENV.delete("GOOGLE_VISION_API_KEY")

    assert_not Transactions::CloudReceiptOcr.enabled?
    assert_nil Transactions::CloudReceiptOcr.call(@photo)
  end

  private
    def ocr_with(body) = Transactions::CloudReceiptOcr.new(@photo, http: ->(_request) { ok(body) })

    def ok(body)
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@body, body.to_json)
      response.instance_variable_set(:@read, true)
      response
    end

    # Builds a Cloud Vision response from rows of [word, left x] at 80px row spacing,
    # rotating every word box by the given tilt like a slanted photo would.
    def vision_response(rows, tilt_degrees: 0, full_text: nil)
      angle = tilt_degrees * Math::PI / 180
      rotate = ->(x, y) { { x: (x * Math.cos(angle) - y * Math.sin(angle)).round, y: (x * Math.sin(angle) + y * Math.cos(angle)).round } }
      words = rows.each_with_index.flat_map do |row, index|
        top = 200 + index * 80
        row.map do |text, left|
          right = left + text.length * 40
          { description: text, boundingPoly: { vertices: [
            rotate.(left, top), rotate.(right, top), rotate.(right, top + 40), rotate.(left, top + 40)
          ] } }
        end
      end
      text = full_text || rows.map { |row| row.map(&:first).join(" ") }.join("\n")
      { responses: [ { textAnnotations: [ { description: text } ] + words, fullTextAnnotation: { text: } } ] }
    end
end
