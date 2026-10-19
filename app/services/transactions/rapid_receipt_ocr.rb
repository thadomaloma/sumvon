require "open3"
require "tempfile"
require "vips"

module Transactions
  # Reads receipt text with RapidOCR, which runs PaddleOCR's models on the server: free,
  # offline, and far better than Tesseract at Japanese thermal print, bold totals, and
  # labels on tinted bank slips. It runs as a Python script in its own virtualenv,
  # named by RECEIPT_OCR_PYTHON (the Docker image sets it up).
  #
  # Returns the text with each printed row rebuilt on one line, or nil when RapidOCR
  # isn't installed or fails, so callers fall back to Tesseract.
  class RapidReceiptOcr
    SCRIPT = Rails.root.join("lib/receipt_ocr/read_receipt.py").to_s
    # Receipt text stays legible at this size, and OCR time grows with pixels.
    MAX_EDGE = 2_048
    TIMEOUT_SECONDS = 15
    MAX_OUTPUT_BYTES = 2.megabytes

    def self.python = ENV["RECEIPT_OCR_PYTHON"].presence

    def self.enabled? = python.present? && File.executable?(python)

    def self.call(photo) = (new(photo).call if enabled?)

    # runner: anything that takes an image path and returns the script's JSON; tests pass a fake.
    def initialize(photo, runner: nil)
      @photo = photo
      @runner = runner || method(:run_script)
    end

    def call
      Tempfile.create([ "receipt-ocr", ".jpg" ]) do |file|
        file.binmode
        file.write(ReceiptPhoto.jpeg(@photo, max_edge: MAX_EDGE))
        file.flush

        pieces = JSON.parse(@runner.call(file.path)).map { |line| ReceiptRows.piece(line["text"], line["box"]) }
        ReceiptRows.text(pieces).presence
      end
    rescue ReadError, JSON::ParserError, Vips::Error, SystemCallError => error
      Rails.error.report(error, handled: true, context: { receipt_ocr: "rapidocr" })
      nil
    end

    class ReadError < StandardError; end

    private
      def run_script(image_path)
        stdin, stdout, stderr, waiter = Open3.popen3(self.class.python, SCRIPT, image_path)
        stdin.close
        output_reader = Thread.new { stdout.read(MAX_OUTPUT_BYTES + 1) }
        error_reader = Thread.new { stderr.read(16.kilobytes) }

        unless waiter.join(TIMEOUT_SECONDS)
          Process.kill("KILL", waiter.pid)
          waiter.join
          raise ReadError, "RapidOCR took longer than #{TIMEOUT_SECONDS} seconds"
        end

        output = output_reader.value.to_s.force_encoding(Encoding::UTF_8)
        raise ReadError, "RapidOCR failed: #{error_reader.value.to_s.lines.last(3).join.strip}" unless waiter.value.success?
        raise ReadError, "RapidOCR output is too large" if output.bytesize > MAX_OUTPUT_BYTES
        output
      ensure
        [ stdin, stdout, stderr ].compact.each { |io| io.close unless io.closed? }
      end
  end
end
