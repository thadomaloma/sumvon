require "csv"

module Transactions
  class JapanBankStatementParser
    class ParseError < StandardError; end

    Entry = Data.define(:date, :kind, :amount, :description, :source_line)
    MAX_ROWS = 3_000

    DATE_HEADERS = %w[日付 取引日 お取引日 勘定日 取扱日 年月日 お取引年月日 預入・払出日 預入払出日 起算日].freeze
    DESCRIPTION_HEADERS = %w[
      お取扱内容 お取り扱い内容 預入・支払内容 預入／支払内容 預入支払内容
      取扱内容 取引内容 送金人名等 振込依頼人名 摘要 摘要内容 詳細1 詳細2
      EDI情報 EDI情報等 内容 明細 取引名 メモ
    ].freeze
    WITHDRAWAL_HEADERS = %w[お支払金額 支払金額 支払額 出金額 出金金額 出金 払出金額 払出額 お引出し額].freeze
    DEPOSIT_HEADERS = %w[お預り金額 お預かり金額 預り金額 預入額 入金額 入金金額 入金 お預入れ額].freeze
    AMOUNT_HEADERS = %w[取引金額 金額].freeze
    KIND_HEADERS = %w[入払区分 入出金区分 受払区分 取引区分 区分].freeze
    BALANCE_HEADERS = %w[残高 取引後残高 現在（貸付）高 現在貸付高].freeze

    def self.from_csv(contents, bank: "auto") = new(bank:).parse_csv(contents)
    def self.from_pdf_text(contents, bank: "auto") = new(bank:).parse_pdf_text(contents)

    def initialize(bank: "auto")
      @bank = bank.to_s
    end

    def parse_csv(contents)
      table = CSV.parse(utf8(contents), headers: false)
      header_index = table.index { |row| header_row?(row) }
      raise ParseError, "The bank statement columns could not be recognized." unless header_index

      headers = table.fetch(header_index).map { |value| normalize_header(value) }
      entries = table.drop(header_index + 1).each_with_index.filter_map do |row, index|
        parse_cells(headers.zip(row).to_h, source_line: header_index + index + 2)
      end
      validate_entries(entries)
    rescue CSV::MalformedCSVError, EncodingError
      raise ParseError, "The CSV file is invalid or uses an unsupported encoding."
    end

    def parse_pdf_text(contents)
      lines = contents.to_s.lines.map(&:chomp)
      header_index = lines.index { |line| header_row?(line) }
      raise ParseError, "The PDF statement table could not be recognized." unless header_index

      columns = pdf_columns(lines.fetch(header_index))
      entries = lines.drop(header_index + 1).each_with_index.filter_map do |line, index|
        parse_cells(slice_pdf_line(line, columns), source_line: header_index + index + 2)
      end
      validate_entries(entries)
    end

    private
      def utf8(contents)
        raw = contents.to_s
        candidate = raw.dup.force_encoding(Encoding::UTF_8)
        return candidate if candidate.valid_encoding?

        raw.dup.force_encoding(Encoding::Windows_31J).encode(Encoding::UTF_8)
      end

      def header_row?(row)
        values = Array(row).join(" ")
        header_present?(values, DATE_HEADERS) &&
          ((header_present?(values, WITHDRAWAL_HEADERS) && header_present?(values, DEPOSIT_HEADERS)) ||
            header_present?(values, AMOUNT_HEADERS))
      end

      def header_present?(value, candidates)
        normalized = normalize_header(value)
        candidates.any? { |candidate| normalized.include?(normalize_header(candidate)) }
      end

      def normalize_header(value)
        value.to_s.unicode_normalize(:nfkc).delete(" \t\r\n　").delete_prefix("﻿")
      end

      def value_for(cells, candidates)
        candidates.each do |candidate|
          value = cells[normalize_header(candidate)]
          return value if value.present?
        end
        nil
      end

      def values_for(cells, candidates)
        candidates.filter_map { |candidate| cells[normalize_header(candidate)].presence }
          .map { |value| value.to_s.strip }.reject(&:blank?).uniq
      end

      def value_with_header(cells, candidates)
        candidates.each do |candidate|
          header = normalize_header(candidate)
          return [ cells[header], header ] if cells[header].present?
        end
        [ nil, nil ]
      end

      def parse_cells(cells, source_line:)
        cells = cells.transform_keys { |key| normalize_header(key) }
        date_value = value_for(cells, DATE_HEADERS)
        return if date_value.blank?

        withdrawal = parse_amount(value_for(cells, WITHDRAWAL_HEADERS))
        deposit = parse_amount(value_for(cells, DEPOSIT_HEADERS))
        amount = parse_amount(value_for(cells, AMOUNT_HEADERS), signed: true)
        kind_raw, kind_header = value_with_header(cells, KIND_HEADERS)
        kind_value = normalize_header(kind_raw)
        return if withdrawal.nil? && deposit.nil? && amount.nil?

        kind, magnitude = classify(withdrawal:, deposit:, amount:, kind_value:, kind_header:)
        raise ParseError, "Line #{source_line} has an ambiguous deposit or withdrawal amount." unless kind && magnitude&.positive?

        Entry.new(date: parse_date(date_value), kind:, amount: magnitude.to_s,
          description: values_for(cells, DESCRIPTION_HEADERS).join(" · ").first(240), source_line:)
      rescue Date::Error, ArgumentError
        raise ParseError, "Line #{source_line} contains an invalid date or amount."
      end

      def classify(withdrawal:, deposit:, amount:, kind_value:, kind_header:)
        return [ :expense, withdrawal ] if withdrawal&.positive? && deposit.nil?
        return [ :income, deposit ] if deposit&.positive? && withdrawal.nil?
        return [ :expense, amount.abs ] if amount&.negative?
        return [ :income, amount ] if amount&.positive? && kind_value.match?(/入金|預入|振込入|受入|受取|CRDT/i)
        return [ :expense, amount ] if amount&.positive? && kind_value.match?(/出金|支払|引出|払出|DBIT/i)
        return [ :income, amount ] if amount&.positive? && kind_header == normalize_header("入払区分") && kind_value == "1"
        return [ :expense, amount ] if amount&.positive? && kind_header == normalize_header("入払区分") && kind_value == "2"
        [ nil, nil ]
      end

      def parse_amount(value, signed: false)
        text = value.to_s.unicode_normalize(:nfkc).strip
        return if text.blank? || text == "-"

        negative = text.match?(/\A[-▲△]|\A\(.*\)\z/)
        number = text.delete(",¥￥円 ").delete_prefix("+").delete_prefix("-")
          .delete_prefix("▲").delete_prefix("△").delete_prefix("(").delete_suffix(")")
        decimal = BigDecimal(number)
        return if decimal.zero?
        signed && negative ? -decimal : decimal.abs
      rescue ArgumentError
        raise ParseError, "The statement contains an invalid amount."
      end

      def parse_date(value)
        text = value.to_s.unicode_normalize(:nfkc).strip
        return japanese_era_date(text) if text.match?(/\A(?:令和|R|平成|H)\s*\d+/i)
        return compact_six_digit_date(text) if text.match?(/\A\d{6}\z/)
        return Date.strptime(text, "%Y年%m月%d日") if text.include?("年")
        return Date.strptime(text, "%Y%m%d") if text.match?(/\A\d{8}\z/)
        Date.parse(text)
      end

      def japanese_era_date(text)
        match = text.match(/\A(令和|R|平成|H)\s*(\d+)(?:年|[\.\/\-])\s*(\d+)(?:月|[\.\/\-])\s*(\d+)日?\z/i)
        raise Date::Error unless match

        offset = %w[令和 R].include?(match[1].upcase) ? 2018 : 1988
        Date.new(offset + match[2].to_i, match[3].to_i, match[4].to_i)
      end

      def compact_six_digit_date(text)
        year = text.first(2).to_i
        # MUFG and Chiba corporate exports define YYMMDD as a Japanese-era date.
        year += 2018 if %w[mufg chiba_bank].include?(@bank)
        year += 2000 if year < 100
        Date.new(year, text[2, 2].to_i, text[4, 2].to_i)
      end

      def validate_entries(entries)
        raise ParseError, "No transaction rows were found in the statement." if entries.empty?
        raise ParseError, "Bank statements are limited to #{MAX_ROWS} rows." if entries.size > MAX_ROWS
        entries
      end

      def pdf_columns(header)
        matches = {
          date: find_header_position(header, DATE_HEADERS),
          description: find_header_position(header, DESCRIPTION_HEADERS),
          withdrawal: find_header_position(header, WITHDRAWAL_HEADERS),
          deposit: find_header_position(header, DEPOSIT_HEADERS),
          kind: find_header_position(header, KIND_HEADERS),
          balance: find_header_position(header, BALANCE_HEADERS)
        }.compact
        matches[:amount] = find_header_position(header, AMOUNT_HEADERS) unless matches[:withdrawal] || matches[:deposit]
        raise ParseError, "The PDF statement columns could not be recognized." unless matches[:date] &&
          ((matches[:withdrawal] && matches[:deposit]) || matches[:amount])

        ordered = matches.sort_by { |_name, position| position }
        ordered.each_with_index.to_h do |(name, position), index|
          next_position = ordered.dig(index + 1, 1)
          [ name, position...next_position ]
        end
      end

      def find_header_position(header, candidates)
        candidates.filter_map { |candidate| header.index(candidate) }.min
      end

      def slice_pdf_line(line, columns)
        columns.to_h do |name, range|
          candidate = range.end ? line[range] : line[range.begin..]
          [ normalize_header_name(name), candidate.to_s.strip ]
        end
      end

      def normalize_header_name(name)
        normalize_header({ date: DATE_HEADERS.first, description: DESCRIPTION_HEADERS.first,
          withdrawal: WITHDRAWAL_HEADERS.first, deposit: DEPOSIT_HEADERS.first,
          amount: AMOUNT_HEADERS.first, kind: KIND_HEADERS.first, balance: BALANCE_HEADERS.first }.fetch(name))
      end
  end
end
