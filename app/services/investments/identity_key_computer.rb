# frozen_string_literal: true

module Investments
  # Computes the canonical `identity_key` for an InvestmentHolding so two
  # writers that see the same real-world security/account produce the
  # same key (and thus the unique index collapses them to one row).
  #
  # See docs/INVESTMENT_ARCHITECTURE.html §5.2 for the rule table.
  #
  # Returns nil when the holding lacks enough data to produce a stable
  # key (manual real_estate, user-typed crypto with no exchange, …).
  # In that case the holding behaves like today (no cross-source dedup,
  # name-based matching as a fallback).
  module IdentityKeyComputer
    extend self

    ISIN_RE = /\A[A-Z]{2}[A-Z0-9]{9}\d\z/.freeze # ISO 6166

    def call(holding)
      attrs = extract_attrs(holding)
      ac = attrs[:asset_class].to_s
      key = compute(ac, attrs)
      sanitize(key)
    end

    # Stand-alone form for unit tests / writers that want to compute
    # from a plain hash rather than an Active Record object. Mirrors the
    # field-alias mapping that #extract_attrs does so callers can pass
    # holding-style attributes (folio, symbol, etc.) without worrying
    # about which internal alias the compute rule reads.
    def from_attrs(asset_class:, **rest)
      attrs = rest.symbolize_keys
      attrs[:deposit_no] ||= attrs[:folio]
      attrs[:account_no] ||= attrs[:folio]
      attrs[:bank_name] ||= attrs[:provider]
      attrs[:amc]       ||= attrs[:provider]
      attrs[:platform]  ||= attrs[:provider]
      attrs[:company]   ||= attrs[:provider]
      attrs[:asset_class] = asset_class.to_s
      sanitize(compute(asset_class.to_s, attrs))
    end

    private

    def compute(asset_class, a)
      case asset_class
      when 'stock'                then a[:isin].presence || ticker_key(a)
      when 'mutual_fund'          then a[:isin].presence || mf_folio_key(a)
      when 'bond', 'sgb'          then a[:isin].presence
      when 'reit', 'invit'        then a[:isin].presence
      when 'fd'                   then deposit_key('FD', a)
      when 'rd'                   then deposit_key('RD', a)
      when 'ppf'                  then passbook_key('PPF', a)
      when 'sukanya'              then passbook_key('SSY', a)
      when 'epf'                  then a[:uan].presence&.then { |u| "EPF:#{u}" }
      when 'nps'                  then pran_key(a)
      when 'rsu'                  then employer_grant_key('RSU', a)
      when 'espp'                 then employer_grant_key('ESPP', a)
      when 'esop'                 then employer_grant_key('ESOP', a)
      when 'p2p'                  then p2p_key(a)
      when 'fractional_re'        then fre_key(a)
      when 'crypto'               then crypto_key(a)
      when 'gold'                 then a[:provider].present? && a[:folio].present? ? "GOLD:#{a[:provider]}:#{a[:folio]}" : nil
      else                             nil
      end
    end

    def extract_attrs(holding)
      meta = holding.metadata.is_a?(Hash) ? holding.metadata.symbolize_keys : {}
      account_provider = holding.investment_account&.provider.presence ||
                         holding.investment_account&.name

      isin = meta[:isin].presence
      isin ||= holding.symbol if holding.symbol.to_s.match?(ISIN_RE)

      {
        asset_class:     holding.asset_class,
        isin:            isin,
        symbol:          holding.symbol,
        folio:           holding.folio,
        name:            holding.name,
        provider:        account_provider,
        exchange:        meta[:exchange],
        amc:             meta[:amc] || account_provider,
        bank_ifsc:       meta[:bank_ifsc],
        bank_name:       meta[:bank_name] || account_provider,
        pran:            meta[:pran],
        uan:             meta[:uan],
        company:         meta[:company] || account_provider,
        grant_id:        meta[:grant_id],
        purchase_period: meta[:purchase_period],
        platform:        meta[:platform] || account_provider,
        property_id:     meta[:property_id],
        investor_id:     meta[:investor_id] || meta[:account_no],
        deposit_no:      holding.folio || meta[:deposit_no],
        account_no:      holding.folio || meta[:account_no],
      }
    end

    def ticker_key(a)
      return nil unless a[:symbol].present?

      exch = (a[:exchange].presence || 'NSE').to_s.upcase
      "TICKER:#{exch}:#{a[:symbol].to_s.upcase}"
    end

    def mf_folio_key(a)
      return nil unless a[:folio].present?

      amc = (a[:amc].presence || a[:provider]).to_s.strip
      return nil if amc.blank?

      "FOLIO:#{amc}:#{a[:folio]}"
    end

    def deposit_key(prefix, a)
      bank = (a[:bank_ifsc].presence || a[:bank_name].presence || a[:provider]).to_s.strip
      no   = a[:deposit_no].to_s.strip
      return nil if bank.blank? || no.blank?

      "#{prefix}:#{bank}:#{no}"
    end

    def passbook_key(prefix, a)
      bank = (a[:bank_ifsc].presence || a[:bank_name].presence || a[:provider]).to_s.strip
      no   = a[:account_no].to_s.strip
      return nil if bank.blank? || no.blank?

      "#{prefix}:#{bank}:#{no}"
    end

    def pran_key(a)
      return nil if a[:pran].blank?

      tier = a[:asset_class].to_s == 'nps_t2' ? 'NPS_T2' : 'NPS'
      "#{tier}:#{a[:pran]}"
    end

    def employer_grant_key(prefix, a)
      return nil if a[:company].blank?

      identifier = case prefix
                   when 'ESPP' then a[:purchase_period]
                   else a[:grant_id]
                   end
      return nil if identifier.blank?

      "#{prefix}:#{a[:company]}:#{identifier}"
    end

    def p2p_key(a)
      return nil if a[:platform].blank? || a[:investor_id].blank?

      "P2P:#{a[:platform]}:#{a[:investor_id]}"
    end

    def fre_key(a)
      return nil if a[:platform].blank? || a[:property_id].blank?

      "FRE:#{a[:platform]}:#{a[:property_id]}:#{a[:investor_id] || 'self'}"
    end

    def crypto_key(a)
      return nil if a[:symbol].blank?

      exch = (a[:provider].presence || a[:platform]).to_s.strip
      return nil if exch.blank?

      "CRYPTO:#{exch}:#{a[:symbol].to_s.upcase}"
    end

    def sanitize(key)
      return nil if key.blank?

      key.to_s.gsub(/\s+/, ' ').strip
    end
  end
end
