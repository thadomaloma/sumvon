require "open3"

module Transactions
  class PdfTextExtractor
    class ExtractionError < StandardError; end

    MAX_TEXT_BYTES = 5.megabytes
    TIMEOUT_SECONDS = 10

    def self.call(file) = new(file).call

    def initialize(file) = @file = file

    def call
      verify_pdf!
      stdin, stdout, stderr, waiter = Open3.popen3("pdftotext", "-layout", "-enc", "UTF-8", @file.path.to_s, "-")
      stdin.close
      output_reader = Thread.new { stdout.read(MAX_TEXT_BYTES + 1) }
      error_reader = Thread.new { stderr.read(16.kilobytes) }

      unless waiter.join(TIMEOUT_SECONDS)
        Process.kill("KILL", waiter.pid)
        waiter.join
        raise ExtractionError, "PDF processing took too long."
      end

      output = output_reader.value.to_s
      error = error_reader.value
      raise ExtractionError, "The PDF is too large after text extraction." if output.bytesize > MAX_TEXT_BYTES
      raise ExtractionError, error.presence || "The PDF could not be read." unless waiter.value.success?
      raise ExtractionError, "The PDF has no readable text. Upload an exported PDF, not a scanned image." if output.strip.blank?

      output
    rescue Errno::ENOENT
      raise ExtractionError, "PDF import is temporarily unavailable."
    ensure
      [ stdin, stdout, stderr ].compact.each { |io| io.close unless io.closed? }
    end

    private
      def verify_pdf!
        raise ExtractionError, "The uploaded file is not a valid PDF." unless @file.respond_to?(:path)
        signature = File.binread(@file.path, 5)
        raise ExtractionError, "The uploaded file is not a valid PDF." unless signature == "%PDF-"
      rescue EOFError, Errno::ENOENT
        raise ExtractionError, "The uploaded file is not a valid PDF."
      end
  end
end
