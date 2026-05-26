# frozen_string_literal: true

module InvestmentImports
  # Parses a CDSL Consolidated Account Statement (CAS PDF) — the depository
  # document that consolidates equity demat holdings across all your brokers
  # plus mutual fund folios in a single document.
  #
  # MVP scope:
  #   * **MF folio transactions** — full transaction history with real amounts
  #     (SIP, Purchase, Redemption, IDCW). This covers the bulk of typical
  #     portfolios (in the sample we tested: 76.9% of value was in MF folios).
  #     Each scheme becomes its own InvestmentHolding under a single
  #     "Mutual Funds (CAS)" account.
  #   * **Equity holdings snapshot** — current units + market value per ISIN,
  #     grouped by broker (one InvestmentAccount per DP). CDSL only shows unit
  #     deltas (no buy prices) for equity, so we model the closing position as
  #     a single 'transfer_in' transaction dated at FY end with
  #     `amount = market_value`. This is a proxy for cost basis; users can
  #     refine later via per-broker CSV imports.
  #
  # Output: array of row Hashes compatible with InvestmentLedgerImporter, each
  # carrying an `:account_hint` key the cdsl_cas-aware Importer uses to route
  # the row to the right InvestmentAccount.
  class CdslCasParser < BaseParser
    NUMBER = /-?[\d,]*\.?\d+/

    # AMC name lines inside the MF transactions section. Example real-world
    # values from the sample: "AxisMutualFund", "CanaraRobecoMutualFund".
    AMC_LINE = /\A([A-Z][A-Za-z& ]*MutualFund)\z/

    # Scheme code line right under the AMC. Examples:
    #   SCGP-AxisSmallCapFund-RegularGrowth
    #   ETGP-CanaraRobecoELSSTaxSaverFund-RegularGrowth
    #   TSRG-MiraeAssetELSSTaxSaverFund(formerlyMiraeAssetTaxSaverFund)-RegularPlan
    SCHEME_LINE = /\A([A-Z0-9]{3,6})-(.+)\z/

    # ISIN line right under the scheme. ISINs are 12 chars: "IN" + 10 alnum.
    ISIN_LINE = /ISIN:\s*(IN[A-Z0-9]{10})/

    # Account-details lines on pages 4–5 are the only place broker (DP) names
    # are rendered cleanly. We map BO IDs → friendly DP names from here.
    DP_NAME_AND_ID = /DPName:\s*([A-Z][A-Z0-9 &.\-]+?)\s+DPID:\s*(\d{8})\s+CLIENTID:\s*(\w+)/i

    # Per-broker section headers in the demat section carry the BO ID with
    # mangled DP names (Hindi glyphs overlap the English label).
    BO_ID_LINE = /BO\s*[I]+\s*[D]?\s*:\s*(\d{16})/i

    # Equity holding row in the "HOLDING STATEMENT" block of each broker.
    # Layout: ISIN  <name>  current  frozen  pledge_bal  pledge_setup  free
    #         price  market_value
    EQUITY_HOLDING_LINE = /
      \A(?<isin>IN[A-Z0-9]{10})\s+
      (?<name>.+?)\s+
      (?<current>#{NUMBER})\s+
      (?:--|#{NUMBER})\s+
      (?:--|#{NUMBER})\s+
      (?:--|#{NUMBER})\s+
      (?:--|#{NUMBER})\s+
      (?<price>#{NUMBER})\s+
      (?<value>#{NUMBER})\s*\z
    /x

    def parse
      text = if @content.is_a?(String) && !@content.start_with?('%PDF') && @content.include?("\n")
               @content
             else
               StatementParsing::TextExtractor.extract(@content, extension: 'pdf')
             end

      lines = text.lines.map(&:rstrip)

      dp_registry = build_dp_registry(lines)
      mf_rows     = parse_mf_folios(lines)
      eq_rows     = parse_equity_holdings(lines, dp_registry)

      (mf_rows + eq_rows).compact
    end

    private

    # First pass: scan for clean "DPName:XXX  DPID:NNNNNNNN CLIENTID:NNNNNNNN"
    # lines so we can later map BO IDs (DPID+CLIENTID concatenated) to DP names.
    def build_dp_registry(lines)
      registry = {}
      lines.each do |line|
        next unless (m = line.match(DP_NAME_AND_ID))

        bo_id = "#{m[2]}#{m[3]}"
        registry[bo_id] ||= friendly_dp(m[1].strip)
      end
      registry
    end

    # Maps raw concatenated DP corporate names to human-friendly broker labels.
    # Falls back to a stripped/titlecased form for unknown brokers.
    KNOWN_BROKERS = {
      /INDSTOCKS/i           => 'INDStocks',
      /GROWW(INVEST)?(TECH)?/i => 'Groww',
      /UPSTOX/i              => 'Upstox',
      /AXIS\s*SECURITIES/i   => 'Axis Securities',
      /ZERODHA/i             => 'Zerodha',
      /ICICI\s*(DIRECT|SEC)/i => 'ICICI Direct',
      /HDFC\s*SECURITIES/i   => 'HDFC Securities',
      /KOTAK\s*SECURITIES/i  => 'Kotak Securities',
      /MOTILAL\s*OSWAL/i     => 'Motilal Oswal',
      /ANGEL\s*ONE/i         => 'Angel One',
    }.freeze

    def friendly_dp(raw)
      KNOWN_BROKERS.each do |pattern, label|
        return label if raw.match?(pattern)
      end
      raw.gsub(/PRIVATELIMITED|PRIVATE\s*LIMITED|LIMITED|LTD\.?/i, '')
         .gsub(/\s+/, ' ')
         .strip
         .titleize
         .presence || 'Demat Account'
    end

    # ───────────────────────── MF Folio section ─────────────────────────

    # We don't pre-seek the MF section — the AMC/scheme/ISIN context naturally
    # stays nil until we hit the first AMC header. Lines elsewhere in the PDF
    # (equity transactions/holdings) never accidentally match the MF txn shape
    # because they don't start with a DD-MM-YYYY token.
    def parse_mf_folios(lines)
      rows = []
      amc = scheme = isin = nil

      lines.each do |line|
        stripped = line.strip
        next if stripped.empty?

        if (m = stripped.match(AMC_LINE))
          amc = humanise_amc(m[1])
          scheme = isin = nil
          next
        end

        if amc && (m = stripped.match(SCHEME_LINE))
          candidate = m[2].split(/ISIN:/i).first.to_s.strip
          if candidate.length.between?(3, 200)
            scheme = humanise_scheme(candidate)
            isin = nil
          end
          # Don't `next` — same line might also carry an ISIN sometimes.
        end

        if (m = line.match(ISIN_LINE))
          isin = m[1]
        end

        next unless scheme && line.match?(/\A\d{2}-\d{2}-\d{4}/)

        tx = parse_mf_txn(line, amc: amc, scheme: scheme, isin: isin)
        rows << tx if tx
      end

      rows
    end

    # MF transaction line layout (sample):
    #   09-02-2026 SystematicInvestment(1/  2999.85  103.71  103.71  28.925  .15  0  0
    # Columns after the description: amount, NAV, price, units, stamp, income,
    # withdrawal (7 numbers). Description tokens sit between the date and the
    # first of the 7 trailing numbers.
    def parse_mf_txn(line, amc:, scheme:, isin:)
      tokens = line.split(/\s+/).reject(&:empty?)
      return nil unless tokens.size >= 9 && tokens[0].match?(/\A\d{2}-\d{2}-\d{4}\z/)

      numeric_tail = tokens.last(7)
      return nil unless numeric_tail.all? { |t| t.match?(/\A-?[\d.,]+\z/) }

      desc_tokens = tokens[1..-8]
      desc = desc_tokens.join(' ').strip
      return nil if desc.empty? || desc.match?(/opening|closing/i)

      amount = numeric_tail[0].delete(',').to_f
      units  = numeric_tail[3].delete(',').to_f
      return nil unless amount.positive?

      date = parse_dmy(tokens[0])
      return nil unless date

      r = row(
        date: date,
        kind: map_mf_kind(desc),
        amount: amount,
        description: isin.present? ? "#{scheme} (#{isin})" : scheme,
        asset_class: 'mutual_fund',
        symbol: isin,
        units: units.positive? ? units : nil,
      )
      return nil unless r

      r.merge(
        account_hint: InvestmentImports::Importer::MUTUAL_FUNDS_CAS_ACCOUNT_NAME,
        meta_kind: 'mf_txn',
        amc: amc,
      )
    end

    def map_mf_kind(desc)
      d = desc.to_s.downcase
      return 'sell'     if d.match?(/redemption|switch[-\s]?out|withdraw/)
      return 'dividend' if d.match?(/dividend|idcw/)
      return 'sip'      if d.match?(/sip|systematic/)
      'buy' # Purchase, Switch-in, fallback
    end

    def humanise_amc(name)
      name.gsub(/MutualFund\z/i, ' Mutual Fund').squeeze(' ').strip
    end

    def humanise_scheme(name)
      name.gsub('-', ' - ')
          .gsub(/([a-z])([A-Z])/, '\1 \2')
          .squeeze(' ')
          .strip
    end

    # ───────────────────────── Equity holdings ─────────────────────────

    def parse_equity_holdings(lines, dp_registry)
      rows = []
      current_dp = nil
      snapshot_date = Date.new(@fy + 1, 3, 31)

      lines.each_with_index do |line, idx|
        if (m = line.match(BO_ID_LINE))
          current_dp = dp_registry[m[1]] || "DP #{m[1]}"
          next
        end

        next unless current_dp && (m = line.match(EQUITY_HOLDING_LINE))

        isin  = m[:isin]
        units = m[:current].delete(',').to_f
        value = m[:value].delete(',').to_f
        next unless units.positive? && value.positive?

        name = stitch_security_name(lines, idx, m[:name])

        # ISIN in the description ensures unique holdings even when the
        # multi-line PDF name extraction collapses two distinct securities
        # to the same short label (e.g. both HDFCFLEXICAPFUND and
        # HDFCSILVERETFFOF stitch down to just "HDFCAMCLTD" in their first
        # extractable line).
        #
        # ISIN prefix is the authoritative asset-class marker on the NSE/BSE:
        #   INE... = Equity (corporate stock)
        #   INF... = Mutual fund (MFs can also be held in demat form via a
        #            broker, so this branch matters — they were silently
        #            mis-classified as stocks before).
        # Other prefixes (IN0/IN1/...) cover bonds/debentures/G-secs which
        # we lump as 'other' for now.
        r = row(
          date: snapshot_date,
          kind: 'transfer_in',
          amount: value,
          description: "#{name} (#{isin})",
          asset_class: asset_class_for(isin),
          symbol: isin,
          units: units,
        )
        next unless r

        rows << r.merge(
          account_hint: current_dp,
          meta_kind: 'equity_snapshot',
        )
      end

      rows
    end

    # Stock names wrap across 2–3 PDF lines because the column is narrow.
    # We do a *conservative* stitch: only the immediately-preceding indented
    # line (when it doesn't look like a tail-fragment of the previous row).
    # Better column-aware extraction would need pdftotext -layout, which isn't
    # universally available; users can rename inaccurate names in the UI.
    TAIL_FRAGMENT_RE = /\A(GROWTH|DIVISION|SUBDIVISION|SHARES|PLAN|DIRECT|REGULAR|FUND|AFTERSUB|AFTER|DIRPL|RE\.\d|VALUERE)/i

    def stitch_security_name(lines, idx, inline_name)
      parts = [inline_name.to_s.strip]

      prev = lines[idx - 1]
      if prev && !prev.strip.empty? && prev =~ /\A\s+\S/ &&
         !prev.match?(EQUITY_HOLDING_LINE) && !prev.match?(BO_ID_LINE) &&
         !prev.strip.match?(TAIL_FRAGMENT_RE)
        parts.unshift(prev.strip)
      end

      clean_security_name(parts.join(' '))
    end

    # The "name" column carries an "#EQSH..." style annotation tail and may
    # be glued without spacing. Strip the tail and normalise whitespace.
    def clean_security_name(raw)
      raw.to_s
         .gsub(/#.*\z/, '')
         .gsub(/\s+/, ' ')
         .strip
    end

    # ───────────────────────── Helpers ─────────────────────────

    def asset_class_for(isin)
      case isin.to_s[0, 3]
      when 'INE' then 'stock'
      when 'INF' then 'mutual_fund'
      else 'other'
      end
    end

    def parse_dmy(str)
      d, m, y = str.split('-')
      Date.new(y.to_i, m.to_i, d.to_i)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
