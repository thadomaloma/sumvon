require "vips"

module Transactions
  # Accepts only real JPEG, PNG, and HEIC photos of a sane size before anything decodes
  # them, and prepares the copy sent to an outside reading service.
  module ReceiptPhoto
    class Invalid < StandardError; end

    SIGNATURES = [ "\xFF\xD8\xFF".b, "\x89PNG\r\n\x1A\n".b ].freeze
    # DNG and most camera RAW formats are TIFF containers.
    TIFF_SIGNATURES = [ "II*\x00".b, "MM\x00*".b ].freeze
    HEIF_BRANDS = %w[heic heix hevc hevx mif1 msf1].freeze
    MAX_BYTES = 25.megabytes

    def self.verify!(file)
      raise Invalid, "Choose a receipt photo." unless file.respond_to?(:path)
      raise Invalid, "Receipt photos are limited to 25 MB." if File.size(file.path) > MAX_BYTES

      signature = File.binread(file.path, 12).to_s.b
      heif = signature.byteslice(4, 4) == "ftyp" && HEIF_BRANDS.include?(signature.byteslice(8, 4))
      if TIFF_SIGNATURES.any? { |magic| signature.start_with?(magic) }
        raise Invalid, "RAW (ProRAW/DNG) photos can't be scanned. Choose a JPEG or HEIC photo."
      end
      raise Invalid, "The uploaded file is not a JPEG, PNG, or HEIC image." unless heif || SIGNATURES.any? { |magic| signature.start_with?(magic) }
    rescue EOFError, Errno::ENOENT
      raise Invalid, "The uploaded file is not a JPEG, PNG, or HEIC image."
    end

    # Shrinks the photo, applies its rotation, and re-encodes it as JPEG without
    # metadata, so neither HEIC nor location data leaves the server.
    def self.jpeg(file, max_edge:)
      Vips::Image.thumbnail(file.path.to_s, max_edge, height: max_edge, size: :down).jpegsave_buffer(Q: 85, strip: true)
    end
  end
end
