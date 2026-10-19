require "test_helper"
require "tempfile"

class Transactions::PdfTextExtractorTest < ActiveSupport::TestCase
  test "rejects a file without a PDF signature" do
    file = Tempfile.new([ "not-a-pdf", ".pdf" ])
    file.write("plain text")
    file.rewind

    error = assert_raises(Transactions::PdfTextExtractor::ExtractionError) do
      Transactions::PdfTextExtractor.call(file)
    end

    assert_match(/not a valid PDF/, error.message)
  ensure
    file&.close!
  end

  test "reports a malformed PDF instead of raising when extraction has no output" do
    file = Tempfile.new([ "broken", ".pdf" ])
    file.write("%PDF-1.7\nnot a real PDF")
    file.rewind

    error = assert_raises(Transactions::PdfTextExtractor::ExtractionError) do
      Transactions::PdfTextExtractor.call(file)
    end

    assert_match(/PDF could not be read|Syntax Error/, error.message)
  ensure
    file&.close!
  end
end
