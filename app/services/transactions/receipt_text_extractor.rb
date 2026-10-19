require "open3"
require "tempfile"
require "vips"

module Transactions
  class ReceiptTextExtractor
    class ExtractionError < StandardError; end

    MAX_IMAGE_BYTES = ReceiptPhoto::MAX_BYTES
    # Rejects decompression bombs before decoding; real photos up to 200 MP pass.
    MAX_SOURCE_PIXELS = 250_000_000
    # Photos are shrunk to this long edge before OCR. A 12 MP phone photo is barely
    # touched, while 48+ MP photos stop costing seconds of extra OCR time.
    MAX_SCAN_EDGE = 3_200
    MAX_TEXT_BYTES = 1.megabyte
    TIMEOUT_SECONDS = 15
    # Total OCR budget for one receipt, so a hopeless photo can't hold a web thread. It
    # stays well under Thruster's 30-second request timeout, upload time included.
    DEADLINE_SECONDS = 20
    MAX_LINE_SCANS = 120

    def self.call(file) = new(file).call

    def initialize(file, deadline_seconds: DEADLINE_SECONDS)
      @file = file
      @deadline = monotonic_now + deadline_seconds
    end

    def call
      verify_image!
      image = load_image

      # Tesseract's automatic layout (psm 3) and single-block mode (psm 6) each lose
      # different lines on real photos; the parser weighs what both found.
      full_texts = Tempfile.create([ "receipt-normalized", ".png" ]) do |file|
        image.write_to_file(file.path)
        [ extract_text(file.path), full_block_text(file.path) ]
      end
      focused_text = focused_text_from(image)
      output = [ *full_texts, focused_text ].reject(&:blank?).join("\n")
      if Transactions::ReceiptScan.call(output).amount.nil? && total_label_seen?(output)
        total_line = scan_total_lines(image)
        output = [ output, total_line ].reject(&:blank?).join("\n")
      end
      raise ExtractionError, "No readable text was found on the receipt." if output.blank?

      output
    rescue Vips::Error
      raise ExtractionError, "The receipt photo could not be read."
    end

    private
      def load_image
        source = Vips::Image.new_from_file(@file.path.to_s)
        raise ExtractionError, "The receipt photo is too large to scan." if source.width * source.height > MAX_SOURCE_PIXELS

        # thumbnail applies EXIF rotation and shrinks while decoding; keep the result in
        # memory because the line scan crops it many times.
        Vips::Image.thumbnail(@file.path.to_s, MAX_SCAN_EDGE, height: MAX_SCAN_EDGE, size: :down).copy_memory
      end

      # Line-by-line scanning is only worth its cost when OCR saw a total label but not
      # its amount; on a slip whose labels OCR can't read it just burns the time budget.
      def total_label_seen?(text)
        normalized = text.unicode_normalize(:nfkc).gsub(/(?<=[一-龯ぁ-んァ-ン])\s+(?=[一-龯ぁ-んァ-ン])/, "")
        normalized.match?(Transactions::ReceiptScan::PAYABLE_LABEL) || normalized.match?(Transactions::ReceiptScan::TOTAL_LABEL)
      end

      def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def full_block_text(path)
        extract_text(path, page_segmentation: 6)
      rescue ExtractionError
        nil
      end

      def focused_text_from(image)
        return if image.height < 100

        top = (image.height * 0.4).floor
        focus = image.crop(0, top, image.width, image.height - top)
        focus = focus.resize(1.5) if image.width < 1_200
        Tempfile.create([ "receipt-focus", ".png" ]) do |file|
          focus.write_to_file(file.path)
          extract_text(file.path, page_segmentation: 6)
        end
      rescue ExtractionError, Vips::Error
        nil
      end

      def scan_total_lines(image)
        return if image.height < 300

        line_height = [ (image.width * 0.046 / 10).round * 10, 60 ].max
        line_height = [ line_height, image.height ].min
        left = (image.width * 0.15 / 10).round * 10
        width = (image.width * 0.6 / 10).round * 10
        step = [ (line_height / 14.0).round, 5 ].max
        ranges = [ [ 0.35, 0.6 ], [ 0.2, 0.35 ], [ 0.6, 0.8 ] ]
        scan_count = 0

        ranges.each do |start_fraction, end_fraction|
          first = (image.height * start_fraction).floor
          last = [ (image.height * end_fraction).floor, image.height - line_height ].min
          candidates = []
          first_candidate_top = nil
          first.step(last, step) do |top|
            break if first_candidate_top && top > first_candidate_top + line_height / 2
            return if scan_count >= MAX_LINE_SCANS

            line = image.crop(left, top, width, line_height)
            scan_count += 1
            text = Tempfile.create([ "receipt-total-line", ".png" ]) do |file|
              line.write_to_file(file.path)
              extract_text(file.path, page_segmentation: 7)
            end
            # OCR reads ¥ as "\" as often as not. Only a labelled total counts; a single
            # item price on its own line would otherwise look like the answer.
            next unless text.match?(/[¥￥$\\]\s*[~〜]?\s*\d/) && total_label_seen?(text)
            next unless Transactions::ReceiptScan.call(text).amount

            first_candidate_top ||= top
            candidates << [ text.match?(/[~〜?]/) ? 0 : 1, top, text ]
          end
          return candidates.max_by { |quality, top, _text| [ quality, top ] }&.last if candidates.any?
        end

        nil
      rescue ExtractionError, Vips::Error
        nil
      end

      def extract_text(path, page_segmentation: nil)
        timeout = [ TIMEOUT_SECONDS, @deadline - monotonic_now ].min
        raise ExtractionError, "Reading the receipt took too long." unless timeout.positive?

        command = [ "tesseract", path.to_s, "stdout", "-l", "eng+jpn" ]
        command.concat([ "--psm", page_segmentation.to_s ]) if page_segmentation
        stdin, stdout, stderr, waiter = Open3.popen3(*command)
        stdin.close
        output_reader = Thread.new { stdout.read(MAX_TEXT_BYTES + 1) }
        error_reader = Thread.new { stderr.read(16.kilobytes) }

        unless waiter.join(timeout)
          Process.kill("KILL", waiter.pid)
          waiter.join
          raise ExtractionError, "Reading the receipt took too long."
        end

        output = (output_reader.value || String.new).force_encoding(Encoding::UTF_8)
        error = error_reader.value
        raise ExtractionError, "The receipt photo is too large after text extraction." if output.bytesize > MAX_TEXT_BYTES
        raise ExtractionError, error.presence || "The receipt photo could not be read." unless waiter.value.success?
        output
      rescue Errno::ENOENT
        raise ExtractionError, "Receipt scanning is temporarily unavailable."
      ensure
        [ stdin, stdout, stderr ].compact.each { |io| io.close unless io.closed? }
      end

      def verify_image!
        ReceiptPhoto.verify!(@file)
      rescue ReceiptPhoto::Invalid => error
        raise ExtractionError, error.message
      end
  end
end
