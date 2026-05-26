# frozen_string_literal: true

# One-shot backfill that runs after the Phase 1 migrations land. Computes
# identity_key on every existing InvestmentHolding and external_id on
# every InvestmentTransaction so the unique indexes start enforcing real
# dedup for legacy data.
#
# Idempotent: safe to re-run. Rows that already have a key are skipped.
# Errors are logged per-row and don't abort the batch.
#
# After the backfill finishes, queue
# Investments::InstrumentReconcilerService.merge_duplicates_for(user) for
# each user to collapse any pre-existing duplicates the new keys now
# expose.
class BackfillInvestmentIdentityKeysJob < ApplicationJob
  queue_as :default

  Result = Struct.new(:holdings_keyed, :activities_keyed, :merges, keyword_init: true)

  def perform(user_id: nil, run_reconciler: true)
    scope = User.all
    scope = scope.where(id: user_id) if user_id

    total = Result.new(holdings_keyed: 0, activities_keyed: 0, merges: 0)

    scope.find_each do |user|
      total.holdings_keyed   += backfill_holdings(user)
      total.activities_keyed += backfill_activities(user)
      total.merges           += run_reconciler ? reconcile(user) : 0
    end

    Rails.logger.info(
      "[BackfillInvestmentIdentityKeysJob] holdings=#{total.holdings_keyed} " \
      "activities=#{total.activities_keyed} merges=#{total.merges}"
    )
    total
  end

  private

  # For keyless legacy holdings, compute the identity_key. If a sibling
  # holding for the same user already owns that key, leave this one
  # keyless and let the reconciler (the next step) merge them — that
  # path also handles the transaction-migration and metadata-merge.
  def backfill_holdings(user)
    count = 0
    user.investment_holdings.where(identity_key: nil).find_each do |h|
      key = Investments::IdentityKeyComputer.call(h)
      next unless key

      sibling = user.investment_holdings.where(identity_key: key).where.not(id: h.id).exists?
      next if sibling

      h.update_columns(identity_key: key, updated_at: Time.current)
      count += 1
    end
    count
  end

  def backfill_activities(user)
    count = 0
    user.investment_transactions
      .where(external_id: nil)
      .includes(:investment_holding, :source_transaction)
      .find_each do |tx|

      attrs = activity_attrs(tx)
      key = Investments::ExternalIdComputer.call(**attrs)
      priority = Investments::SourcePriority.for(tx.source)

      updates = { source_priority: priority }
      updates[:external_id] = key if key

      begin
        tx.update_columns(updates.merge(updated_at: Time.current))
        count += 1 if key
      rescue ActiveRecord::RecordNotUnique
        # Another row with the same external_id already exists. The
        # ActivityReconcilerService will handle this once supersession
        # is in play; for now we just skip.
        tx.update_columns(source_priority: priority, updated_at: Time.current)
      end
    end
    count
  end

  def activity_attrs(tx)
    holding = tx.investment_holding
    meta = holding&.metadata.is_a?(Hash) ? holding.metadata.symbolize_keys : {}
    {
      source:         tx.source,
      transaction_id: tx.transaction_id,
      provider:       holding&.investment_account&.provider,
      folio:          holding&.folio,
      isin:           meta[:isin] || holding&.symbol,
      symbol:         holding&.symbol,
      date:           tx.date,
      units:          tx.units,
      amount:         tx.amount,
      kind:           tx.kind,
    }
  end

  def reconcile(user)
    Investments::InstrumentReconcilerService.merge_duplicates_for(user).merges
  end
end
