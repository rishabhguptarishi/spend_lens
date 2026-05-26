# frozen_string_literal: true

require "rails_helper"

RSpec.describe Investments::NavFetcher, type: :service do
  let(:http) { instance_double(Net::HTTPSuccess, body: stub_body, is_a?: true) }
  let(:stub_body) do
    {
      meta: {
        scheme_code: "120503",
        isin_growth: "INF769K01101",
        scheme_name: "Mirae Asset Large Cap Fund - Direct Growth",
        fund_house: "Mirae Asset Mutual Fund",
        scheme_type: "Open Ended Schemes",
        scheme_category: "Equity Scheme - Large Cap Fund",
      },
      data: [
        { date: "25-05-2026", nav: "75.1234" },
        { date: "24-05-2026", nav: "74.8500" },
      ],
    }.to_json
  end

  let(:fake_client) do
    Class.new do
      def initialize(response)
        @response = response
      end

      def request_http(_uri, _req)
        @response
      end
    end.new(http)
  end

  subject(:fetcher) { described_class.new(http_client: fake_client) }

  describe "#fetch by scheme_code" do
    it "creates a cache row on first lookup" do
      cache = fetcher.fetch(scheme_code: "120503")
      expect(cache).to be_a(MfNavCache)
      expect(cache.nav.to_f).to eq(75.1234)
      expect(cache.nav_date).to eq(Date.new(2026, 5, 25))
      expect(cache.isin).to eq("INF769K01101")
      expect(cache.amc).to eq("Mirae Asset Mutual Fund")
      expect(cache).to be_fresh
    end

    it "returns the cached row without re-fetching on subsequent calls within FRESH_FOR" do
      first = fetcher.fetch(scheme_code: "120503")
      expect(fake_client).to receive(:request_http).never  # second call shouldn't hit the API
      second = fetcher.fetch(scheme_code: "120503")
      expect(second.id).to eq(first.id)
    end

    it "re-fetches when force_refresh is true even if cache is fresh" do
      fetcher.fetch(scheme_code: "120503")
      expect(fake_client).to receive(:request_http).once.and_return(http)
      fetcher.fetch(scheme_code: "120503", force_refresh: true)
    end
  end

  describe "graceful degradation" do
    it "returns nil when the API errors and there is no cache" do
      bad_client = Class.new do
        def request_http(_uri, _req)
          raise SocketError, "down"
        end
      end.new

      bad = described_class.new(http_client: bad_client)
      expect(bad.fetch(scheme_code: "999999")).to be_nil
    end

    it "returns the stale cache when present but the API fails" do
      MfNavCache.create!(scheme_code: "120503", nav: 70.0, nav_date: Date.new(2026, 1, 1), fetched_at: 5.days.ago)

      bad_client = Class.new do
        def request_http(_uri, _req)
          raise SocketError, "down"
        end
      end.new

      result = described_class.new(http_client: bad_client).fetch(scheme_code: "120503")
      expect(result).to be_a(MfNavCache)
      expect(result).to be_stale
    end
  end
end
