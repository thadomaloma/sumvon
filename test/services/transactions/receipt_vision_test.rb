require "test_helper"
require "tempfile"
require "vips"

class Transactions::ReceiptVisionTest < ActiveSupport::TestCase
  FakeBlock = Struct.new(:type, :text)
  FakeResponse = Struct.new(:stop_reason, :content)

  # Stands in for Anthropic::Client and records the request it receives.
  class FakeClient
    attr_reader :request

    def initialize(&respond) = @respond = respond
    def beta = self
    def messages = self

    def create(**request)
      @request = request
      @respond.call
    end
  end

  setup do
    @photo = Tempfile.new([ "receipt", ".jpg" ])
    @photo.close
    Vips::Image.black(3_000, 4_000).write_to_file(@photo.path)
  end

  teardown { @photo.close! }

  test "reads an ATM withdrawal as a transfer" do
    client = fake_client('{"amount":"200000","date":"2026-10-04","kind":"atm_withdrawal"}')

    result = Transactions::ReceiptVision.new(@photo, client:).call

    assert_equal BigDecimal("200000"), result.amount
    assert_equal Date.new(2026, 10, 4), result.date
    assert_equal "transfer", result.kind
  end

  test "reads a store receipt as a plain purchase" do
    result = Transactions::ReceiptVision.new(@photo, client: fake_client('{"amount":"1,098","date":"2026-10-04","kind":"purchase"}')).call

    assert_equal BigDecimal("1098"), result.amount
    assert_nil result.kind
  end

  test "sends a shrunken JPEG without metadata and asks for structured output" do
    client = fake_client('{"amount":"500","date":null,"kind":"purchase"}')

    Transactions::ReceiptVision.new(@photo, client:).call

    assert_equal :"claude-opus-5", client.request[:model]
    assert_equal :json_schema, client.request.dig(:output_config, :format_, :type)
    image = client.request.dig(:messages, 0, :content, 0)
    sent = Vips::Image.new_from_buffer(Base64.decode64(image.dig(:source, :data)), "")
    assert_equal "image/jpeg", image.dig(:source, :media_type)
    assert_equal Transactions::ReceiptVision::MAX_EDGE, sent.height
  end

  test "drops implausible dates but keeps the amount" do
    result = Transactions::ReceiptVision.new(@photo, client: fake_client('{"amount":"500","date":"2099-01-01","kind":"purchase"}')).call

    assert_equal BigDecimal("500"), result.amount
    assert_nil result.date
  end

  test "returns nil so OCR can try when the amount is unreadable, refused, or the API fails" do
    assert_nil Transactions::ReceiptVision.new(@photo, client: fake_client('{"amount":null,"date":null,"kind":"other"}')).call
    assert_nil Transactions::ReceiptVision.new(@photo, client: fake_client('{"amount":"500"}', stop_reason: :refusal)).call
    assert_nil Transactions::ReceiptVision.new(@photo, client: fake_client("not json")).call

    failing = FakeClient.new { raise Anthropic::Errors::APIConnectionError.new(url: nil, request: nil) }
    assert_nil Transactions::ReceiptVision.new(@photo, client: failing).call
  end

  test "is off without an API key" do
    original = ENV.delete("ANTHROPIC_API_KEY")
    assert_not Transactions::ReceiptVision.enabled?
    assert_nil Transactions::ReceiptVision.call(@photo)
  ensure
    ENV["ANTHROPIC_API_KEY"] = original if original
  end

  private
    def fake_client(json, stop_reason: :end_turn)
      FakeClient.new { FakeResponse.new(stop_reason, [ FakeBlock.new(:thinking, nil), FakeBlock.new(:text, json) ]) }
    end
end
