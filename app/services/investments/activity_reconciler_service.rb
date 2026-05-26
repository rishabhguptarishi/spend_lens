# frozen_string_literal: true

module Investments
  # Phase 2 reconciler #2: find activities across sources that describe
  # the same real-world event, then link them via confirmed_by /
  # superseded_by_id without losing the audit trail.
  #
  # Example: a Zerodha CSV import gives a 'sell' row at priority 80, and
  # the user later uploads CDSL CAS which shows the same sell at priority
  # 100. Both rows persist (so the audit log is complete), but only the
  # depository row is canonical:
  #
  #   activity[priority=80].superseded_by_id  = activity[priority=100].id
  #   activity[priority=100].confirmed_by    += ['broker_import']
  #
  # Rollups (net worth, capital gains) use `InvestmentTransaction.active`
  # which filters out superseded rows. The UI surfaces confirmed_by as
  # source badges on the canonical row.
  #
  # Match criteria (configurable; defaults below):
  #   - Same user
  #   - Same investment_holding_id, OR holdings with the same
  #     identity_key when holding IDs differ
  #   - Same kind  (buy/sell/dividend/…)
  #   - Date within ±1 day
  #   - Amount within ±2% AND ≤ ₹50 absolute delta (whichever is wider)
  class ActivityReconcilerService
    DEFAULT_DATE_DELTA = 1.day
    DEFAULT_AMOUNT_PCT = 0.02
    DEFAULT_AMOUNT_ABS = 50.0

    Result = Struct.new(:activities_examined, :matches, :supersessions, :confirmations, keyword_init: true) do
      def empty?
        matches.zero?
      end
    end

    def initialize(user, since: nil,
                   date_delta: DEFAULT_DATE_DELTA,
                   amount_pct: DEFAULT_AMOUNT_PCT,
                   amount_abs: DEFAULT_AMOUNT_ABS)
      @user = user
      @since = since
      @date_delta = date_delta
      @amount_pct = amount_pct
      @amount_abs = amount_abs
    end

    def self.reconcile_for(user, since: nil)
      new(user, since: since).call
    end

    def call
      activities = scope_activities
      matches = supersessions = confirmations = 0

      grouped = activities.group_by { |a| group_key(a) }

      grouped.each_value do |group|
        next if group.size < 2

        # Process in descending priority so the highest-priority row
        # "wins" and lower rows are superseded by it.
        sorted = group.sort_by { |a| [-a.source_priority.to_i, a.created_at] }
        canonical = sorted.shift

        sorted.each do |other|
          next unless same_event?(canonical, other)

          matches += 1
          if other.source_priority.to_i < canonical.source_priority.to_i
            unless other.superseded_by_id == canonical.id
              other.update!(superseded_by_id: canonical.id)
              supersessions += 1
            end
            confirmations += 1 if canonical.confirm_with!(other.source)
          else
            confirmations += 1 if canonical.confirm_with!(other.source)
          end
        end
      end

      Result.new(
        activities_examined: activities.size,
        matches: matches,
        supersessions: supersessions,
        confirmations: confirmations,
      )
    end

    private

    def scope_activities
      rel = @user.investment_transactions.where(superseded_by_id: nil).includes(:investment_holding)
      rel = rel.where('date >= ?', @since) if @since
      rel.to_a
    end

    # Two activities are candidates for matching when they cover the
    # same instrument (holding-id or identity_key) AND same kind. We
    # then verify date / amount proximity in same_event?.
    def group_key(a)
      instrument_id = a.investment_holding&.identity_key.presence || "holding_id:#{a.investment_holding_id}"
      [instrument_id, a.kind]
    end

    def same_event?(a, b)
      return false if a.id == b.id
      return false if (a.date - b.date).abs > @date_delta
      return false unless amount_within_tolerance?(a.amount.to_f, b.amount.to_f)

      true
    end

    def amount_within_tolerance?(x, y)
      return true if x.zero? && y.zero?

      delta = (x - y).abs
      pct_threshold = [x.abs, y.abs].max * @amount_pct
      delta <= [pct_threshold, @amount_abs].max
    end
  end
end
