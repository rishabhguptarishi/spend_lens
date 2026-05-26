# frozen_string_literal: true

require 'net/http'
require 'json'

module Investments
  # Phase 4 §6 — mfapi.in NAV client + cache.
  #
  # mfapi.in is a free public proxy over AMFI's daily NAV publish. No
  # auth, no rate limits documented, no licensing risk. Endpoints used:
  #
  #   GET https://api.mfapi.in/mf/<scheme_code>      → latest NAV + history
  #   GET https://api.mfapi.in/mf/search?q=<query>   → scheme search
  #
  # Lookup precedence (per #fetch):
  #   1. scheme_code → direct endpoint hit
  #   2. ISIN        → MfNavCache hit (we don't go off-platform for ISIN
  #                    today — that requires an AMFI master file load)
  #   3. name        → search endpoint; first result with similar AMC
  #
  # Failure mode: any network / parsing failure logs at warn and returns
  # nil. PositionComputer's blank_nav fallback path then uses cost_basis
  # as the displayed value, and the UI shows a "live NAV unavailable"
  # badge. Zero crash, zero blocked render.
  class NavFetcher
    BASE_URL = ENV.fetch('MF_NAV_API_BASE', 'https://api.mfapi.in').freeze
    TIMEOUT_SECONDS = 5
    USER_AGENT = "SpendLens/#{Rails.env}".freeze

    def initialize(http_client: nil)
      @http = http_client
    end

    # Return a MfNavCache (fresh or stale) or nil if we couldn't resolve.
    # When `force_refresh` is true, bypass the cache entirely (manual
    # refresh button in the UI calls this).
    def fetch(scheme_code: nil, isin: nil, name: nil, force_refresh: false)
      cache = lookup_cache(scheme_code: scheme_code, isin: isin)
      return cache if cache&.fresh? && !force_refresh

      refresh(cache: cache, scheme_code: scheme_code, isin: isin, name: name) || cache
    end

    private

    def lookup_cache(scheme_code:, isin:)
      return MfNavCache.find_by(scheme_code: scheme_code) if scheme_code.present?
      return MfNavCache.find_by(isin: isin) if isin.present?

      nil
    end

    def refresh(cache:, scheme_code:, isin:, name:)
      payload = fetch_from_api(scheme_code: scheme_code, isin: isin, name: name)
      return nil unless payload

      cache ||= MfNavCache.find_or_initialize_by(
        scheme_code: payload[:scheme_code] || scheme_code,
      )
      cache.scheme_code ||= payload[:scheme_code] || scheme_code
      cache.isin        ||= payload[:isin] || isin
      cache.scheme_name = payload[:scheme_name] if payload[:scheme_name].present?
      cache.amc         = payload[:amc]         if payload[:amc].present?
      cache.nav         = payload[:nav]
      cache.nav_date    = payload[:nav_date]
      cache.fetched_at  = Time.current
      cache.source      = 'mfapi.in'
      cache.metadata    = cache.metadata.is_a?(Hash) ? cache.metadata.merge(payload[:metadata] || {}) : (payload[:metadata] || {})
      cache.save!
      cache
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn "[NavFetcher] cache save failed: #{e.message}"
      nil
    end

    # Try (in order) the scheme_code direct endpoint, then name search.
    # ISIN-only lookup isn't supported by mfapi.in directly today — for
    # CDSL CAS rows we'd need a separate ISIN→scheme_code resolution
    # (AMFI publishes a daily master CSV; that's a Phase 5/6 follow-up).
    def fetch_from_api(scheme_code:, isin: nil, name: nil)
      if scheme_code.present?
        body = http_get("/mf/#{scheme_code}")
        return parse_scheme_response(body) if body
      end

      if name.present?
        body = http_get("/mf/search?q=#{URI.encode_www_form_component(name)}")
        first = parse_search_response(body)&.first
        return nil unless first

        return fetch_from_api(scheme_code: first[:scheme_code])
      end

      nil
    end

    def http_get(path)
      uri = URI.join(BASE_URL, path)
      req = Net::HTTP::Get.new(uri.request_uri)
      req['User-Agent'] = USER_AGENT

      resp = http.request_http(uri, req)
      return nil unless resp.is_a?(Net::HTTPSuccess)

      resp.body
    rescue StandardError => e
      Rails.logger.warn "[NavFetcher] HTTP error #{path}: #{e.class}: #{e.message}"
      nil
    end

    def parse_scheme_response(body)
      json = JSON.parse(body)
      meta = json['meta'] || {}
      latest = (json['data'] || []).first
      return nil unless latest

      {
        scheme_code: meta['scheme_code']&.to_s,
        isin: meta['isin_growth'] || meta['isin_div_reinvestment'],
        scheme_name: meta['scheme_name'],
        amc: meta['fund_house'],
        nav: latest['nav']&.to_f,
        nav_date: parse_date(latest['date']),
        metadata: { scheme_type: meta['scheme_type'], scheme_category: meta['scheme_category'] }.compact,
      }
    rescue JSON::ParserError => e
      Rails.logger.warn "[NavFetcher] JSON parse error: #{e.message}"
      nil
    end

    def parse_search_response(body)
      JSON.parse(body).map { |entry| { scheme_code: entry['schemeCode']&.to_s, scheme_name: entry['schemeName'] } }
    rescue JSON::ParserError, NoMethodError
      []
    end

    def parse_date(str)
      return nil if str.blank?

      Date.strptime(str.to_s, '%d-%m-%Y')
    rescue ArgumentError
      nil
    end

    def http
      @http ||= self
    end

    # Default HTTP transport. Pulled out so specs can stub by passing a
    # client that responds to #request_http(uri, req).
    def request_http(uri, req)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: TIMEOUT_SECONDS, open_timeout: TIMEOUT_SECONDS) do |http|
        http.request(req)
      end
    end
  end
end
