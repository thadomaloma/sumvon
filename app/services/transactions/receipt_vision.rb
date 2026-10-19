require "base64"
require "vips"

module Transactions
  # Reads a receipt or ATM slip photo with Claude. On-server OCR misreads thermal
  # print, bold totals, and labels on tinted bank slips; a vision model reads them
  # the way a person would.
  #
  # Returns a ReceiptScan::Result, or nil whenever Claude isn't configured, can't
  # read the photo, or the API fails — callers then fall back to on-server OCR.
  class ReceiptVision
    MODEL = :"claude-opus-5"
    # Claude reads images up to this long edge; larger photos only cost upload time.
    MAX_EDGE = 1_568

    INSTRUCTIONS = <<~TEXT.freeze
      You read photos of receipts and bank ATM slips, mostly Japanese, for a personal finance app.

      amount: the money that changed hands, as plain digits with an optional decimal point (for example "1098"), without currency symbols or thousands separators.
      - Store, restaurant, or card receipt: the total paid (合計, お会計, ご請求金額, お買上合計, ご利用金額). Never the cash handed over (お預り), change (お釣), subtotal (小計), tax, discounts, points, or a card balance.
      - ATM slip: the transaction amount (お取引金額, お引出金額, お預入金額). Never the fee (手数料) or the balance (残高, お取引後残高).

      date: the transaction date as YYYY-MM-DD. Japanese era years: 令和 or R plus n is 2018 + n; 平成 or H plus n is 1988 + n. Bank slips often print the Reiwa year as two digits, so 08-10-04 means 2026-10-04.

      kind: atm_withdrawal, atm_deposit, purchase (any store, restaurant, or card receipt), or other.

      Use null for an amount or date you cannot read with confidence. Never guess.
    TEXT

    SCHEMA = {
      type: "object",
      properties: {
        amount: { anyOf: [ { type: "string" }, { type: "null" } ] },
        date: { anyOf: [ { type: "string", format: "date" }, { type: "null" } ] },
        kind: { type: "string", enum: %w[purchase atm_withdrawal atm_deposit other] }
      },
      required: %w[amount date kind],
      additionalProperties: false
    }.freeze

    def self.enabled? = ENV["ANTHROPIC_API_KEY"].present?

    def self.call(photo) = (new(photo).call if enabled?)

    def initialize(photo, client: nil)
      @photo = photo
      @client = client
    end

    def call
      response = client.beta.messages.create(
        model: MODEL,
        max_tokens: 4_096,
        system_: INSTRUCTIONS,
        output_config: { effort: :low, format_: { type: :json_schema, schema: SCHEMA } },
        fallbacks: :default,
        betas: [ :"server-side-fallback-2026-07-01" ],
        messages: [ { role: :user, content: [ image_block, { type: :text, text: "Read this photo." } ] } ]
      )
      return unless response.stop_reason == :end_turn

      text = response.content.find { |block| block.type == :text }&.text
      build_result(JSON.parse(text.to_s))
    rescue Anthropic::Errors::Error, JSON::ParserError, Vips::Error => error
      Rails.error.report(error, handled: true, context: { receipt_vision: MODEL })
      nil
    end

    private
      def client
        @client ||= Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"), max_retries: 1, timeout: 45)
      end

      def image_block
        jpeg = ReceiptPhoto.jpeg(@photo, max_edge: MAX_EDGE)
        { type: :image, source: { type: :base64, media_type: "image/jpeg", data: Base64.strict_encode64(jpeg) } }
      end

      def build_result(data)
        amount = parse_amount(data["amount"])
        return unless amount

        ReceiptScan::Result.new(amount:, date: parse_date(data["date"]),
          kind: data["kind"].to_s.start_with?("atm_") ? "transfer" : nil)
      end

      def parse_amount(value)
        amount = BigDecimal(value.to_s.delete(",¥円 "))
        amount if amount.positive?
      rescue ArgumentError
        nil
      end

      def parse_date(value)
        date = Date.iso8601(value.to_s)
        date if date.year >= 2000 && date <= Date.current + 1
      rescue Date::Error
        nil
      end
  end
end
