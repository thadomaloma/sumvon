require "base64"
require "vips"
require "net/http"

module Transactions
  # Reads the text on a receipt photo with Google Cloud Vision, whose Japanese OCR
  # handles thermal print and tinted bank slips far better than on-server Tesseract.
  #
  # Returns the text with each printed row rebuilt on one line (see ReceiptRows), or nil
  # when the service isn't configured or fails, so callers fall back to the next reader.
  class CloudReceiptOcr
    ENDPOINT = URI("https://vision.googleapis.com/v1/images:annotate")
    # Plenty for receipt text, and keeps the upload small.
    MAX_EDGE = 2_048

    def self.enabled? = ENV["GOOGLE_VISION_API_KEY"].present?

    def self.call(photo) = (new(photo).call if enabled?)

    # http: anything that takes a Net::HTTP request and returns a response; tests pass a fake.
    def initialize(photo, http: nil)
      @photo = photo
      @http = http || method(:send_request)
    end

    def call
      response = @http.call(build_request)
      unless response.is_a?(Net::HTTPSuccess)
        return report(RuntimeError.new("Cloud Vision responded #{response.code}"))
      end

      annotation = JSON.parse(response.body).dig("responses", 0) || {}
      return report(RuntimeError.new("Cloud Vision error: #{annotation.dig("error", "message")}")) if annotation["error"]

      [ rows_from(annotation["textAnnotations"]), annotation.dig("fullTextAnnotation", "text") ].compact_blank.join("\n").presence
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, JSON::ParserError, Vips::Error => error
      report(error)
    end

    private
      def build_request
        request = Net::HTTP::Post.new(ENDPOINT)
        request["Content-Type"] = "application/json"
        # Sent as a header so the key never appears in a logged URL.
        request["X-Goog-Api-Key"] = ENV.fetch("GOOGLE_VISION_API_KEY", "")
        request.body = {
          requests: [ {
            image: { content: Base64.strict_encode64(ReceiptPhoto.jpeg(@photo, max_edge: MAX_EDGE)) },
            features: [ { type: "DOCUMENT_TEXT_DETECTION" } ],
            imageContext: { languageHints: %w[ja en] }
          } ]
        }.to_json
        request
      end

      def send_request(request)
        Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, open_timeout: 5, read_timeout: 20) do |http|
          http.request(request)
        end
      end

      def rows_from(annotations)
        pieces = Array(annotations).drop(1).map do |annotation|
          # Cloud Vision omits zero coordinates, so a missing x or y is 0.
          points = annotation.dig("boundingPoly", "vertices")&.map { |vertex| [ vertex["x"].to_f, vertex["y"].to_f ] }
          ReceiptRows.piece(annotation["description"], points)
        end
        ReceiptRows.text(pieces)
      end

      def report(error)
        Rails.error.report(error, handled: true, context: { receipt_ocr: "cloud_vision" })
        nil
      end
  end
end
