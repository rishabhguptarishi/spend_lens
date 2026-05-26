# frozen_string_literal: true

module Investments
  # Phase 2 reconciler #1: collapse holdings that share an identity_key.
  #
  # Two writers seeing the same real-world security/account (same ISIN, or
  # same FD deposit number, or same PPF account number, …) historically
  # forked two parallel InvestmentHolding rows because the legacy lookup
  # keyed off (name, asset_class). Phase 1 added identity_key with a
  # unique index, which prevents the duplication at write time for new
  # rows — but legacy rows (created before the migration) don't have
  # identity_key set and CAN still collide once we backfill.
  #
  # This service handles both situations:
  #   * stored-key duplicates  — shouldn't exist given the unique index,
  #                              but kept as a safety net for raw inserts
  #   * keyless legacy rows    — groups by COMPUTED key, merges, then
  #                              sets identity_key on the survivor
  #
  # Merge rules:
  #   * Winner = oldest holding (created_at asc), so the choice is stable
  #     across re-runs.
  #   * All investment_transactions move from loser → winner (and inherit
  #     the winner's investment_account_id so account-level rollups stay
  #     consistent).
  #   * Metadata merges; winner's keys win conflicts.
  #   * Winner's invested_amount / units are recomputed from the merged
  #     transactions via recompute_totals!.
  #
  # Idempotent. Safe to run on a clean DB.
  class InstrumentReconcilerService
    Result = Struct.new(:groups_examined, :merges, :transactions_moved, keyword_init: true) do
      def empty?
        merges.zero?
      end
    end

    def initialize(user)
      @user = user
    end

    def self.merge_duplicates_for(user)
      new(user).call
    end

    def call
      groups = duplicate_groups
      merges = 0
      txs_moved = 0

      groups.each do |key, holdings|
        winner, *losers = holdings.sort_by(&:created_at)
        next unless losers.any?

        ActiveRecord::Base.transaction do
          losers.each do |loser|
            txs_moved += migrate_transactions(loser, winner)
            merge_metadata(loser, winner)
            loser.destroy!
            merges += 1
          end
          winner.update_columns(identity_key: key) if winner.identity_key.blank?
          # Stale association cache after update_all; reload before
          # recomputing totals so the sum reflects merged rows.
          winner.investment_transactions.reload
          winner.recompute_totals!
        end
      end

      Result.new(
        groups_examined: groups.size,
        merges: merges,
        transactions_moved: txs_moved,
      )
    end

    private

    # Group every holding by an identity_key — preferring the stored
    # value, falling back to a fresh computation for keyless legacy
    # rows. Skip holdings without a computable key (manual real_estate,
    # crypto without exchange, etc.); those can't be dedup'd.
    def duplicate_groups
      groups = Hash.new { |h, k| h[k] = [] }

      @user.investment_holdings.includes(:investment_account).find_each do |h|
        key = h.identity_key.presence || Investments::IdentityKeyComputer.call(h)
        next if key.blank?

        groups[key] << h
      end

      groups.select { |_k, hs| hs.size > 1 }
    end

    def migrate_transactions(loser, winner)
      relation = InvestmentTransaction.where(investment_holding_id: loser.id)
      count = relation.count
      relation.update_all(
        investment_holding_id: winner.id,
        investment_account_id: winner.investment_account_id,
      )
      count
    end

    def merge_metadata(loser, winner)
      base = loser.metadata.is_a?(Hash) ? loser.metadata : {}
      top  = winner.metadata.is_a?(Hash) ? winner.metadata : {}
      merged = base.merge(top) # winner's keys win conflicts
      winner.update!(metadata: merged) if merged != top
    end
  end
end
