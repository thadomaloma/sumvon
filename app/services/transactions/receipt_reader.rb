module Transactions
  # Reads the amount, date, and kind from a receipt or ATM slip photo, using the best
  # reader that is configured: Claude, Google Cloud Vision, then on-server RapidOCR,
  # and Tesseract last. A reader that isn't configured or fails hands over to the next.
  class ReceiptReader
    def self.call(photo) = new(photo).call

    def initialize(photo, vision: ReceiptVision, cloud_ocr: CloudReceiptOcr, local_ocr: RapidReceiptOcr, ocr: ReceiptTextExtractor)
      @photo = photo
      @vision = vision
      @cloud_ocr = cloud_ocr
      @local_ocr = local_ocr
      @ocr = ocr
    end

    def call
      ReceiptPhoto.verify!(@photo)
      @vision.call(@photo) || ReceiptScan.call(@cloud_ocr.call(@photo) || @local_ocr.call(@photo) || @ocr.call(@photo))
    rescue ReceiptPhoto::Invalid => error
      raise ReceiptTextExtractor::ExtractionError, error.message
    end
  end
end
