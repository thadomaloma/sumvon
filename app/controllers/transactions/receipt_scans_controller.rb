class Transactions::ReceiptScansController < ApplicationController
  rate_limit to: 10, within: 1.minute, only: :create,
    with: -> { render json: { error: I18n.t("transactions.scan_receipt_rate_limited") }, status: :too_many_requests }

  def create
    render json: Transactions::ReceiptReader.call(params[:photo])
  rescue Transactions::ReceiptTextExtractor::ExtractionError => error
    render json: { error: error.message }, status: :unprocessable_entity
  end
end
