module Transactions
  # OCR services return text pieces with their boxes, often in column order. Grouping
  # the pieces by height on the page recreates the receipt's printed rows, which keeps
  # each label beside its amount ("合計 ¥1,098"). The page's tilt is measured from the
  # pieces' top edges and undone first, so a slanted photo still lines up.
  module ReceiptRows
    # points: the box corners, top-left first and clockwise.
    def self.piece(text, points)
      return unless text.present? && points&.size == 4

      xs, ys = points.map(&:first), points.map(&:last)
      { text:, x: xs.sum / 4, y: ys.sum / 4, height: ys.max - ys.min,
        angle: Math.atan2(points[1][1] - points[0][1], points[1][0] - points[0][0]) }
    end

    def self.text(pieces)
      pieces = pieces.compact
      return if pieces.empty?

      angle = median(pieces.map { |piece| piece[:angle] })
      pieces = pieces.map { |piece| piece.merge(row: piece[:y] * Math.cos(angle) - piece[:x] * Math.sin(angle)) }
      tolerance = median(pieces.map { |piece| piece[:height] }) * 0.5

      rows = []
      pieces.sort_by { |piece| piece[:row] }.each do |piece|
        if rows.any? && (piece[:row] - rows.last[:row]).abs <= tolerance
          rows.last[:pieces] << piece
        else
          rows << { row: piece[:row], pieces: [ piece ] }
        end
      end
      rows.map { |row| row[:pieces].sort_by { |piece| piece[:x] }.map { |piece| piece[:text] }.join(" ") }.join("\n")
    end

    def self.median(values)
      sorted = values.sort
      sorted[sorted.size / 2]
    end
  end
end
