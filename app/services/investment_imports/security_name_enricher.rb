# frozen_string_literal: true

module InvestmentImports
  # Optional post-processing step that rewrites the `:description` field on
  # parsed CDSL CAS rows from the column-truncated form
  #
  #     "HDFCAMCLTD (INF179K01XQ0)"
  #
  # to the canonical form
  #
  #     "HDFC Mid-Cap Fund - Direct Plan - Growth (INF179K01XQ0)".
  #
  # Strict guarantees (deliberately narrow scope so AI is only fixing what
  # regex can't reach):
  #
  #   1. **Numbers are never touched.** Amounts, units, dates, kinds stay
  #      whatever the deterministic parser produced. The LLM only sees and
  #      returns names; even if it hallucinates an amount, we ignore it.
  #   2. **ISINs are anchored.** We keep the ISIN the parser extracted and
  #      reject any AI-returned ISIN that doesn't match the input — the model
  #      can't smuggle in a different security under our nose.
  #   3. **Failure-tolerant.** Any error (missing key, timeout, malformed
  #      JSON, blocked network, AI disabled) returns the rows unchanged.
  #      The deterministic output is always the floor.
  #   4. **Cached per-ISIN.** Re-importing the same CAS next month, or a
  #      different user's CAS that overlaps in securities, hits Rails.cache
  #      and skips the LLM entirely. ISIN → name is a stable mapping.
  #   5. **One round-trip per import.** All unique ISINs in the batch are
  #      sent in a single prompt (split into chunks of MAX_BATCH if huge).
  class SecurityNameEnricher
    CACHE_NAMESPACE = 'cdsl_cas/security_name'
    CACHE_TTL = 90.days
    MAX_BATCH = 50

    def self.call(rows)
      new(rows).call
    end

    def initialize(rows)
      @rows = rows.to_a
    end

    def call
      # **Default off.** Empirically, even Gemini 2.5 Flash confidently
      # hallucinates mutual-fund names when the raw fragment is just an AMC
      # initialism (e.g. "HDFCAMCLTD" → guessed "HDFC Equity Savings Fund"
      # when the ISIN actually maps to "HDFC Mid-Cap Opportunities Fund").
      # The truncated regex output is at least honest about not knowing.
      # Users who trust their AI provider can opt in with CDSL_CAS_AI_ENRICH=true.
      return @rows if @rows.empty? || ENV['CDSL_CAS_AI_ENRICH'] != 'true'

      pairs = unique_isin_pairs
      return @rows if pairs.empty?

      name_map = pairs.to_h { |isin, _| [isin, cached_name(isin)] }.compact
      uncached = pairs.reject { |isin, _| name_map.key?(isin) }

      if uncached.any?
        ai_names = fetch_names_from_ai(uncached)
        ai_names.each { |isin, name| Rails.cache.write(cache_key(isin), name, expires_in: CACHE_TTL) }
        name_map.merge!(ai_names)
      end

      return @rows if name_map.empty?

      @rows.map { |r| rewrite_description(r, name_map) }
    rescue => e
      Rails.logger.warn "[CDSL CAS] name enrichment failed: #{e.class}: #{e.message}"
      @rows
    end

    private

    def unique_isin_pairs
      seen = {}
      @rows.each do |r|
        isin = (r[:symbol] || r['symbol']).to_s
        next unless valid_isin?(isin)
        next if seen.key?(isin)

        raw = (r[:description] || r['description']).to_s
        next unless rich_enough_to_enrich?(raw, isin)

        seen[isin] = raw
      end
      seen.to_a
    end

    def valid_isin?(isin)
      isin.is_a?(String) && isin.match?(/\AIN[A-Z0-9]{10}\z/)
    end

    # We tested Gemini 2.5 Flash against real CDSL data and observed it
    # hallucinates confidently when the raw fragment is just an AMC
    # initialism (e.g. "HDFCAMCLTD"). With a clear scheme name as a
    # cross-check the model only polishes ("Axis Small Cap Fund - Regular
    # Growth" → "Axis Small Cap Fund - Regular Plan - Growth"). So we only
    # send rows that already carry enough signal for the AI to verify
    # against, not invent from. Cutoff: ≥ 18 chars excluding the ISIN
    # suffix, OR contains a scheme/security keyword.
    SCHEME_KEYWORDS = /\b(fund|limited|ltd|plan|growth|dividend|hybrid|debt|index|etf|liquid)\b/i

    def rich_enough_to_enrich?(raw, isin)
      stripped = raw.gsub(/\s*\(#{Regexp.escape(isin)}\)\s*\z/, '').strip
      stripped.length >= 18 || stripped.match?(SCHEME_KEYWORDS)
    end

    def cache_key(isin)
      "#{CACHE_NAMESPACE}:#{isin}"
    end

    def cached_name(isin)
      Rails.cache.read(cache_key(isin))
    end

    def fetch_names_from_ai(pairs)
      pairs.each_slice(MAX_BATCH).reduce({}) do |acc, slice|
        prompt = build_prompt(slice)
        raw = AiClient.chat(prompt, nil, format: 'json', temperature: 0.0).to_s.strip
        json_string = raw[/\{[\s\S]*\}/] || raw
        parsed = JSON.parse(json_string)

        input_isins = slice.to_h.keys.to_set
        Array(parsed['securities']).each do |item|
          isin = item['isin'].to_s
          name = item['name'].to_s.strip
          next unless input_isins.include?(isin) && name.present? && name.length <= 120

          acc[isin] = name
        end
        acc
      end
    end

    def build_prompt(pairs)
      input = JSON.generate(securities: pairs.map { |isin, raw| { isin: isin, raw: raw } })

      <<~PROMPT
        You normalize Indian security names from a CDSL Consolidated Account
        Statement. The raw fragments are column-truncated by a PDF extractor
        and may be just an AMC initialism (e.g. "HDFCAMCLTD") — they are NOT
        a reliable hint to the underlying scheme.

        **The ISIN is the only authoritative identifier.** Treat the raw
        fragment as noise unless you can verify it independently from your
        knowledge of the ISIN.

        Rules:
        1. If you can identify the security from the ISIN with high confidence,
           return its official name:
              - Equity: "Reliance Industries Limited" (proper case, no annotations).
              - Mutual fund: "HDFC Mid-Cap Opportunities Fund - Direct Plan - Growth"
                (AMC + scheme + plan + option, exact scheme).
        2. If you are NOT highly confident in the ISIN → name mapping, return
           the raw fragment cleaned of "#"-prefixed annotations. **Do not guess.**
           A truncated honest label is much better than a confident wrong one
           — financial users will trust the wrong name and not catch it.
        3. Echo the ISIN verbatim. Never substitute one.
        4. Return ONLY valid JSON. No prose, no markdown, no code fences.

        Input:
        #{input}

        Expected output schema:
        {"securities":[{"isin":"<same isin>","name":"<canonical name OR cleaned raw fragment>"}]}
      PROMPT
    end

    # Format coming in from the CDSL parser is "<raw_name> (<isin>)" — strip
    # the existing name, keep the (ISIN) suffix, and prepend the canonical name.
    # The (ISIN) suffix is preserved so the description remains a unique key
    # for the dedupe logic in InvestmentLedgerImporter.
    def rewrite_description(row, name_map)
      isin = (row[:symbol] || row['symbol']).to_s
      canonical = name_map[isin]
      return row if canonical.blank?

      new_desc = "#{canonical} (#{isin})"
      if row.is_a?(Hash) && row.keys.first.is_a?(String)
        row.merge('description' => new_desc)
      else
        row.merge(description: new_desc)
      end
    end
  end
end
