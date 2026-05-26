import { router } from '@inertiajs/react'
import { useMemo, useState } from 'react'
import DashboardLayout from '../../Layouts/DashboardLayout'

export default function OverlapReview({ statement, overlapping = [] }) {
  const [submitting, setSubmitting] = useState(false)

  const totalExistingTransactions = useMemo(
    () => overlapping.reduce((sum, s) => sum + (s.transaction_count || 0), 0),
    [overlapping]
  )

  const submit = (resolution) => {
    if (submitting) return
    setSubmitting(true)
    router.patch(
      `/statements/${statement.id}/resolve_overlap`,
      { resolution },
      {
        onFinish: () => setSubmitting(false),
        preserveScroll: true,
      }
    )
  }

  return (
    <DashboardLayout title="Overlapping statement detected">
      <div className="max-w-2xl mx-auto">
        <div className="mb-6">
          <h2 className="text-lg font-semibold text-slate-100">Overlapping statement detected</h2>
          <p className="text-slate-400 mt-1">
            Your new upload covers a period that overlaps with existing statements on{' '}
            <span className="text-slate-200">{statement.bank_account?.name}</span>. Choose how to
            proceed before parsing.
          </p>
        </div>

        <section className="sl-card rounded-2xl border border-white/10 p-6 mb-6">
          <h3 className="text-sm font-medium text-slate-300 mb-3">Your new upload</h3>
          <div className="flex items-baseline justify-between">
            <div className="text-slate-100 font-medium">{statement.period_label}</div>
            <div className="text-xs text-slate-500">
              {statement.bank_account?.bank_name} •••• ({statement.bank_account?.name})
            </div>
          </div>
        </section>

        <section className="sl-card rounded-2xl border border-amber-500/30 bg-amber-500/5 p-6 mb-6">
          <h3 className="text-sm font-medium text-amber-200 mb-3">
            Overlaps with {overlapping.length} existing statement{overlapping.length === 1 ? '' : 's'}
            {totalExistingTransactions > 0 && (
              <span className="text-slate-400 font-normal">
                {' '}
                ({totalExistingTransactions} transaction
                {totalExistingTransactions === 1 ? '' : 's'} already saved)
              </span>
            )}
          </h3>
          <ul className="divide-y divide-white/10">
            {overlapping.map((s) => (
              <li key={s.id} className="py-2 flex items-baseline justify-between">
                <span className="text-slate-200">{s.period_label}</span>
                <span className="text-xs text-slate-500">
                  {s.transaction_count} txn{s.transaction_count === 1 ? '' : 's'}
                </span>
              </li>
            ))}
          </ul>
        </section>

        <section className="sl-card rounded-2xl border border-white/10 p-6 space-y-3">
          <h3 className="text-sm font-medium text-slate-300">What would you like to do?</h3>

          <button
            type="button"
            disabled={submitting}
            onClick={() => submit('replace')}
            className="w-full text-left p-4 rounded-lg border border-violet-500/40 bg-violet-500/10 hover:bg-violet-500/15 transition disabled:opacity-50"
          >
            <div className="font-medium text-violet-200">Replace existing statements</div>
            <div className="text-xs text-slate-400 mt-1">
              Delete the {overlapping.length} overlapping statement
              {overlapping.length === 1 ? '' : 's'} (and their transactions, categorizations and any
              attached files) before parsing this new one. Recommended when the new upload supersedes
              the old data (e.g. a full FY statement after individual months).
            </div>
          </button>

          <button
            type="button"
            disabled={submitting}
            onClick={() => submit('keep_both')}
            className="w-full text-left p-4 rounded-lg border border-slate-500/40 bg-slate-500/10 hover:bg-slate-500/15 transition disabled:opacity-50"
          >
            <div className="font-medium text-slate-200">Keep both statements</div>
            <div className="text-xs text-slate-400 mt-1">
              Parse the new upload alongside existing data. Per-transaction deduplication will skip
              rows that exactly match what's already saved — but variants from a different PDF render
              may slip through.
            </div>
          </button>

          <button
            type="button"
            disabled={submitting}
            onClick={() => submit('cancel')}
            className="w-full text-left p-4 rounded-lg border border-red-500/40 bg-red-500/5 hover:bg-red-500/10 transition disabled:opacity-50"
          >
            <div className="font-medium text-red-200">Cancel upload</div>
            <div className="text-xs text-slate-400 mt-1">
              Discard the file and keep your existing data unchanged.
            </div>
          </button>
        </section>
      </div>
    </DashboardLayout>
  )
}
