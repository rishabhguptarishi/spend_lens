# frozen_string_literal: true

module Investments
  # Phase 4 §5.1 — rolls up activities into materialized positions.
  #
  # For each (user, investment_holding, custodian) tuple we:
  #
  #   1. Sum units / amounts across ACTIVE (non-superseded) transactions.
  #      Inflows (buy/sip/contribution/transfer_in) add to cost basis.
  #      Outflows (sell/transfer_out/maturity) reduce it proportionally.
  #   2. Look up live NAV via NavFetcher when the holding is market-priced
  #      (mutual_fund / stock / bond / sgb / reit / invit) and the holding
  #      has enough metadata to identify it (ISIN or scheme_code).
  #   3. Compute current_value = units × NAV when NAV is known.
  #   4. Upsert the InvestmentPosition row.
  #
  # The supersession layer from Phase 1+2 is what makes this safe to call
  # idempotently after any write — superseded rows are filtered out, so
  # double-source data (broker_csv + cdsl_cas of the same trade) doesn't
  # double-count.
  #
  # Custodian inference (per §5.5): we derive the custodian from the
  # investment_account.provider (or fall back to account_kind). The doc
  # has a richer model but we don't need a separate Custodian table for
  # this PR — `custodian` is just a string column on the position.
  class PositionComputer
    INFLOW_KINDS  = %w[buy contribution sip transfer_in].freeze
    OUTFLOW_KINDS = %w[sell transfer_out maturity].freeze
    PRICED_ASSET_CLASSES = %w[mutual_fund stock bond sgb reit invit].freeze

    Result = Struct.new(:created, :updated, :nav_priced, keyword_init: true) do
      def total
        created + updated
      end
    end

    def initialize(user, nav_fetcher: NavFetcher.new)
      @user = user
      @nav_fetcher = nav_fetcher
    end

    def self.recompute_for(user)
      new(user).call
    end

    def call
      created = updated = nav_priced = 0
      grouped = group_active_activities

      seen_position_ids = []

      grouped.each do |(holding_id, custodian), activities|
        holding = InvestmentHolding.find_by(id: holding_id)
        next unless holding

        cost_basis, units = aggregate(activities)
        nav_lookup = lookup_nav(holding, units)

        position_attrs = {
          asset_class:   holding.asset_class,
          units:         units.round(6),
          cost_basis:    cost_basis.round(2),
          current_value: nav_lookup[:current_value],
          current_nav:   nav_lookup[:nav],
          as_of_date:    nav_lookup[:nav_date],
          computed_at:   Time.current,
          metadata: holding.metadata.is_a?(Hash) ? holding.metadata.slice('isin', 'scheme_code', 'amc') : {},
        }

        position = InvestmentPosition.find_or_initialize_by(
          user: @user,
          investment_holding: holding,
          custodian: custodian,
        )
        new_record = position.new_record?
        position.assign_attributes(position_attrs)
        position.save!
        seen_position_ids << position.id

        if new_record
          created += 1
        else
          updated += 1
        end
        nav_priced += 1 if nav_lookup[:current_value].present?
      end

      # Garbage-collect positions whose underlying activities were all
      # deleted (e.g. user removed a tax doc). Without this, /net_worth
      # would keep counting positions for instruments the user no
      # longer owns.
      InvestmentPosition.for_user(@user).where.not(id: seen_position_ids).destroy_all

      Result.new(created: created, updated: updated, nav_priced: nav_priced)
    end

    private

    # Build the grouping: { [holding_id, custodian] => [activities] }.
    # Joins on investment_holding so we filter out activities orphaned
    # by holding destruction. Excludes superseded rows so cross-source
    # dedup actually works.
    def group_active_activities
      @user.investment_transactions
        .active
        .where.not(investment_holding_id: nil)
        .includes(investment_holding: :investment_account)
        .group_by { |t| [t.investment_holding_id, derive_custodian(t.investment_holding)] }
    end

    def derive_custodian(holding)
      account = holding.investment_account
      account&.provider.presence || account&.name.presence || 'unknown'
    end

    def aggregate(activities)
      cost_basis = 0.0
      units      = 0.0

      activities.each do |a|
        amt = a.amount.to_f
        u   = a.units.to_f

        if INFLOW_KINDS.include?(a.kind)
          cost_basis += amt
          units      += u
        elsif OUTFLOW_KINDS.include?(a.kind)
          cost_basis -= amt
          units      -= u
        end
      end

      [[cost_basis, 0].max, [units, 0].max]
    end

    # NAV lookup. Returns {nav:, nav_date:, current_value:} or nils when
    # the holding isn't market-priced, has no ISIN/scheme_code, or the
    # NAV API is offline. The downstream UI degrades gracefully via
    # InvestmentPosition#best_known_value.
    def lookup_nav(holding, units)
      return blank_nav unless PRICED_ASSET_CLASSES.include?(holding.asset_class)
      return blank_nav unless units.positive?

      meta = holding.metadata.is_a?(Hash) ? holding.metadata.symbolize_keys : {}
      isin = meta[:isin].presence || (holding.symbol if holding.symbol.to_s.match?(/\AIN[EF]/))
      scheme_code = meta[:scheme_code].presence

      cache = @nav_fetcher.fetch(isin: isin, scheme_code: scheme_code, name: holding.name)
      return blank_nav unless cache&.nav&.positive?

      {
        nav: cache.nav.to_f,
        nav_date: cache.nav_date,
        current_value: (units * cache.nav.to_f).round(2),
      }
    end

    def blank_nav
      { nav: nil, nav_date: nil, current_value: nil }
    end
  end
end
