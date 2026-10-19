module Transactions
  # Reads the paid amount, date, and kind of slip from OCR'd receipt text, tuned for
  # Japanese supermarket, convenience store, restaurant, card, and ATM slips.
  #
  # OCR of thermal paper is noisy (合計 comes back as 吾計 or "Gat", ¥ as "\"), so the
  # amount is not taken from a single line. Each independent clue votes for an amount —
  # a total label, a payment-method line, cash tendered minus change — and the amount
  # with the strongest agreement wins.
  class ReceiptScan
    # alternatives: other amounts the receipt might mean, offered when the clues are weak.
    Result = Data.define(:amount, :date, :kind, :alternatives) do
      def initialize(amount:, date:, kind:, alternatives: []) = super

      # Form-ready values: "1080" rather than BigDecimal's "1080.0", and an ISO date.
      def as_json(*)
        { amount: self.class.form_amount(amount), date: date&.iso8601, kind:,
          alternatives: alternatives.map { |value| self.class.form_amount(value) } }
      end

      def self.form_amount(value)
        value && (value.frac.zero? ? value.to_i.to_s : value.to_s("F"))
      end
    end

    # "お買上" alone also starts the footer "お買上明細は、上記の通りです", so it needs 合計/計/金額.
    PAYABLE_LABEL = /お支払(?:い)?(?:金額|額)?|ご請求(?:金額)?|お会計|お買上げ?(?:合計|計|金額)|ご利用金額|amount\s*due|grand\s*total/i
    # OCR misreads 合計 as 吾計/台計, "Gat", or splits 計 into 言十 on wide bold print.
    TOTAL_LABEL = /(?:税込|税抜)?総?[合吾台含]計(?:金額)?|[合吾台含明]?言[十二]|\bGa[tl]\b|total(?:\s*amount)?/i
    PAYMENT_LABEL = /支払|クレ[ジシ][ッツ]ト|カード|交通系|電子マネー|PayPay|楽天ペイ|d払い|au\s*PAY|nanaco|WAON|QUICPay|Suica|PASMO|ICOCA/i
    TENDERED_LABEL = /お?預か?り/
    CHANGE_LABEL = /お?釣|釣銭/
    EXCLUDED_LABEL = /小(?:計|言[十二])|税[合吾台]?計|点数|お?預か?り|お?釣|釣銭|税額|消費税|ポイント|残高|現在高|値引|割引|対象|手数料|料金|subtotal|change|tax|balance/i

    # Store receipts also print balances and 支払, so only bank-specific words count.
    # An ATM slip moves money between the person's own accounts, unless it pays
    # someone else (振込).
    BANK_SLIP = /ATM(?:ご利用|明細|取引)|銀行|興銀|信用金庫|信金|ゆうちょ|口座|お取引種別|お取扱日|キャッシュサービス/
    BANK_PAYMENT = /振込/
    # A price marked with ¥ or 円, or grouped in thousands as OCR prints it ("200, 000", "1.098").
    MONEY_LIKE = /[¥\\]\s*\d|\d\s*円|\d[,.]\s?\d{3}(?!\d)/
    BANK_AMOUNT_LABEL = /(?:お?取引|お?引き?出し?|お?預け?入れ?|出|入)?金額|出金|入金/

    SUBTOTAL_LABEL = /小計/
    TAX_LABEL = /(内)?(?:外税|消費税)/
    MARKED_AMOUNT = /[¥\\]\s*\d|\d\s*円/

    WEIGHTS = { payable: 3, bank: 3, total: 2, payment: 2, cash: 2, subtotal_tax: 2 }.freeze

    NUMBER = /(?<currency>[¥$\\])?\s*(?<amount>\d[\d,]*(?:\.\d{1,2})?)\s*(?<yen>円)?/
    WESTERN_DATE = /(?<!\d)(\d{4})\s*[年.\/-]\s*(\d{1,2})\s*[月.\/-]\s*(\d{1,2})(?!\d)/
    ERA_DATE = /(?<![A-Za-z])(令和|平成|R|H)\s*(\d{1,2})\s*[年.\/-]\s*(\d{1,2})\s*[月.\/-]\s*(\d{1,2})(?!\d)/
    MONTH_DAY = /(?<!\d)(\d{1,2})月(\d{1,2})日/
    SHORT_DATE = /(?<![\d\/.-])(\d{2})[.\/-](\d{1,2})[.\/-](\d{1,2})(?![\d\/.-])/
    ERA_START_YEARS = { "令和" => 2018, "R" => 2018, "平成" => 1988, "H" => 1988 }.freeze

    def self.call(text) = new(text).call

    # PaddleOCR's models also read Chinese and sometimes print a kanji in its simplified
    # form (额 for 額); map the ones receipts use back.
    SIMPLIFIED_KANJI = { "额" => "額", "费" => "費", "别" => "別", "种" => "種", "银" => "銀",
      "计" => "計", "预" => "預", "钓" => "釣", "现" => "現", "门" => "門" }.freeze

    def initialize(text)
      @lines = text.to_s.unicode_normalize(:nfkc).gsub(Regexp.union(SIMPLIFIED_KANJI.keys), SIMPLIFIED_KANJI).lines.map do |line|
        line.strip
          .gsub(/(?<=[一-龯ぁ-んァ-ンー])\s+(?=[一-龯ぁ-んァ-ンー])/, "")
          .gsub(/(?<=\d)\s+(?=[年月日])|(?<=[年月])\s+(?=\d)/, "") # OCR spaces out "2026 年 10 月 3 日"
      end.reject(&:blank?)
      @text = @lines.join("\n")
      @yen = @text.match?(/[¥\\]|円/)
      @bank_slip = @text.match?(BANK_SLIP)
      @alternatives = []
    end

    def call
      amount = find_amount
      Result.new(amount:, date: find_date, kind: (@bank_slip && !@text.match?(BANK_PAYMENT) ? "transfer" : nil),
        alternatives: @alternatives)
    end

    private
      def find_amount
        votes = Hash.new { |hash, amount| hash[amount] = {} }
        @lines.each_with_index do |line, index|
          next if line.match?(EXCLUDED_LABEL)

          source, amount = labelled_amount(line, index)
          votes[amount][source] = index if amount
        end
        if (cash = cash_paid)
          votes[cash][:cash] = @lines.size
        end
        # Service charges or discounts can make subtotal + tax differ from the total, so
        # this only backs an amount another clue found; it never proposes one itself.
        if (sum = subtotal_with_tax) && votes.key?(sum)
          votes[sum][:subtotal_tax] = @lines.size
        end
        # A yen total under ¥10 is OCR noise such as a stray "\1".
        votes.reject! { |amount, _sources| @yen && amount < 10 }
        return (@bank_slip ? first_bank_amount : only_marked_amount || offer_printed_amounts) if votes.empty?

        ranked = votes.sort_by do |_amount, sources|
          weights = sources.keys.map { |source| WEIGHTS[source] }
          [ -weights.sum, -weights.max, -sources.values.max ]
        end
        best_amount, best_sources = ranked.first
        # Two agreeing clues are convincing; otherwise offer the runners-up too.
        @alternatives = ranked.drop(1).map(&:first).first(2) if best_sources.keys.sum { |source| WEIGHTS[source] } < 4
        best_amount
      end

      # No label survived OCR, so don't guess: offer the printed amounts for the person
      # to pick from.
      def offer_printed_amounts
        @alternatives = printed_amounts_by_likelihood.first(3)
        nil
      end

      # A receipt prints its total several times (the total, the taxable base, the
      # payment) while most items appear once, so frequent and large amounts come first.
      def printed_amounts_by_likelihood
        counts = @lines.select { |line| line.match?(MONEY_LIKE) && !line.match?(EXCLUDED_LABEL) }
          .filter_map { |line| parse_amount(line) }.select { |amount| amount >= 10 }.tally
        counts.sort_by { |amount, count| [ -count, -amount ] }.map(&:first)
      end

      def printed_amounts
        @lines.select { |line| line.match?(MONEY_LIKE) && !line.match?(EXCLUDED_LABEL) }
          .filter_map { |line| parse_amount(line) }.select { |amount| amount >= 10 }.uniq
      end

      # When OCR lost every label on an ATM slip, the transaction amount is the first
      # money figure printed; the balance comes after it and the fee line is excluded.
      def first_bank_amount
        amounts = printed_amounts
        @alternatives = amounts.drop(1).first(2)
        amounts.first
      end

      def labelled_amount(line, index)
        if @bank_slip && (label = line.match(BANK_AMOUNT_LABEL))
          [ :bank, amount_after(label, index) ]
        elsif (label = line.match(PAYABLE_LABEL))
          [ :payable, amount_after(label, index) ]
        elsif (label = line.match(TOTAL_LABEL))
          [ :total, amount_after(label, index) ]
        elsif line.match?(PAYMENT_LABEL)
          [ :payment, parse_amount(line, marked_only: true) ]
        end
      end

      # The amount sits after its label, or alone on the next line when OCR splits columns.
      def amount_after(label, index)
        amount = parse_amount(label.post_match)
        following = @lines[index + 1]
        amount ||= parse_amount(following) if following && !following.match?(/[[:alpha:]一-龯ぁ-んァ-ン]/)
        amount
      end

      def cash_paid
        tendered = @lines.select { |line| line.match?(TENDERED_LABEL) }.filter_map { |line| parse_amount(line) }.last
        changes = @lines.select { |line| line.match?(CHANGE_LABEL) }
        # "お釣 ¥0" parses as no amount, so only an explicit zero counts as zero change.
        change = changes.filter_map { |line| parse_amount(line) }.last
        change ||= 0 if changes.any? { |line| line.match?(/[¥\\]\s*0(?!\d)|(?<!\d)0\s*円/) }
        return unless tendered && change

        paid = tendered - change
        paid if paid.positive?
      end

      # Exclusive tax ("外税") is added to the subtotal; inclusive tax ("内税") is not.
      # Only trusted on simple receipts with one subtotal and at most one tax figure.
      def subtotal_with_tax
        subtotals = @lines.select { |line| line.match?(SUBTOTAL_LABEL) }.filter_map { |line| parse_amount(line) }.uniq
        tax_lines = @lines.select { |line| line.match?(TAX_LABEL) && !line.match?(SUBTOTAL_LABEL) && !line.match?(/対象/) }
        taxes = tax_lines.filter_map { |line| [ line.match(TAX_LABEL)[1].present?, parse_amount(line) ] if parse_amount(line) }.uniq
        return unless subtotals.one? && taxes.size <= 1

        inclusive, tax = taxes.first
        inclusive || tax.nil? ? nil : subtotals.first + tax
      end

      # A card slip whose labels OCR mangled may still show its one price. Only trusted
      # when the whole text holds a single price, so an item line is never mistaken for it.
      def only_marked_amount
        priced = @lines.select { |line| line.match?(MARKED_AMOUNT) }
        amounts = priced.filter_map { |line| parse_amount(line, marked_only: true) }.uniq
        return unless amounts.one?

        amounts.first if priced.any? { |line| !line.match?(EXCLUDED_LABEL) && parse_amount(line, marked_only: true) == amounts.first }
      end

      def parse_amount(line, marked_only: false)
        return if line.blank?

        text = line.gsub(ERA_DATE, " ").gsub(WESTERN_DATE, " ").gsub(SHORT_DATE, " ").gsub(/\d{1,2}:\d{2}/, " ")
        text = text.gsub(/(?<=[¥$\\])\s*[~〜]\s*/, "")
        text = text.gsub(/(?<=\d)[.,]\s*(?=\d{3}(?!\d))/, ",")
        amounts = text.to_enum(:scan, NUMBER).filter_map do
          match = Regexp.last_match
          digits = match[:amount]
          marked = match[:currency].present? || match[:yen].present?
          next if marked_only && !marked
          next if match.pre_match.match?(/[-−△▲]\s*\z/)
          next if match.post_match.match?(/\A\s*(?:点|個|枚|件|%|pt)/i)
          # OCR often reads a trailing 円 as one extra digit ("50,0004"); other broken
          # grouping like "3,27" comes from a misread digit, so never guess from it.
          if digits.include?(",") && !digits.match?(/\A\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?\z/)
            next unless (grouped = digits[/\A\d{1,3}(?:,\d{3})+(?=\d\z)/])
            digits = grouped
          end

          amount = BigDecimal(digits.delete(","))
          next if amount.zero? || (@yen && !amount.frac.zero?)
          [ marked ? 1 : 0, amount ]
        rescue ArgumentError
          nil
        end
        amounts.max_by { |marked, amount| [ marked, amount ] }&.last
      end

      def find_date
        lines = @lines.reject { |line| line.match?(/期限|有効/) }
        lines.each do |line|
          date = parse_date(line)
          return date if date
        end
        lines.each do |line|
          date = month_day_date(line)
          return date if date
        end
        nil
      end

      # OCR sometimes keeps only "10月4日" of the date line; assume the most recent such day.
      def month_day_date(line)
        match = line.match(MONTH_DAY)
        return unless match

        date = build_date(Date.current.year, match[1], match[2])
        date = build_date(Date.current.year - 1, match[1], match[2]) if date && date > Date.current + 1
        date
      end

      def parse_date(line)
        date = if (match = line.match(ERA_DATE))
          build_date(ERA_START_YEARS.fetch(match[1]) + match[2].to_i, match[3], match[4])
        elsif (match = line.match(WESTERN_DATE))
          build_date(match[1], match[2], match[3])
        elsif (match = line.match(SHORT_DATE))
          short_year_date(match[1].to_i, match[2], match[3])
        end
        date if date && date.year >= 2000 && date <= Date.current + 1
      end

      # "26-09-30" is a western year, but bank slips print the Reiwa year ("08-10-04"
      # is Reiwa 8, 2026). Take whichever reading is the most recent date not in the future.
      def short_year_date(year, month, day)
        [ 2000 + year, ERA_START_YEARS.fetch("令和") + year ]
          .filter_map { |candidate| build_date(candidate, month, day) }
          .select { |date| date <= Date.current + 1 }.max
      end

      def build_date(year, month, day)
        Date.new(year.to_i, month.to_i, day.to_i)
      rescue Date::Error
        nil
      end
  end
end
