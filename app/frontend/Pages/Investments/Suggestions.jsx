import { Link, router } from '@inertiajs/react'
import { useMemo, useState } from 'react'
import DashboardLayout from '../../Layouts/DashboardLayout'

// Phase 4 §5.7 row 2 — bucketed by match confidence so users can triage
// with appropriate caution. The three buckets are computed server-side
// (InvestmentSuggestion#compute_match_bucket); this component just
// renders them as tabs with bucket-aware bulk actions.

const ASSET_LABELS = {
  mutual_fund: 'Mutual fund',
  stock: 'Stock',
  bond: 'Bond',
  fd: 'FD',
  rd: 'RD',
  nps: 'NPS',
  ppf: 'PPF',
  crypto: 'Crypto',
  reit: 'REIT',
  invit: 'InvIT',
  other: 'Other',
}

const BUCKET_ORDER = ['auto_resolved', 'likely_match', 'unknown']

const BUCKET_DESCRIPTIONS = {
  auto_resolved: 'Strong match — narration includes a unique folio or account number we can fold into an existing holding. Safe to bulk-accept.',
  likely_match: 'Named platform or AMC matched, but no folio was captured. Worth a quick scan before accepting.',
  unknown: 'Generic keyword match (e.g. "SIP" or "INV") — please review individually.',
}

const BUCKET_BADGE_CLASSES = {
  auto_resolved: 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30',
  likely_match: 'bg-violet-500/15 text-violet-300 border-violet-500/30',
  unknown: 'bg-amber-500/15 text-amber-300 border-amber-500/30',
}

function formatInr(n) {
  return `₹${Number(n || 0).toLocaleString('en-IN')}`
}

export default function InvestmentsSuggestions({
  suggestions = [],
  buckets = { auto_resolved: 0, likely_match: 0, unknown: 0 },
  bucket_labels: bucketLabels = {},
}) {
  const total = suggestions.length
  const [activeBucket, setActiveBucket] = useState(() => {
    return BUCKET_ORDER.find((b) => buckets[b] > 0) || 'auto_resolved'
  })

  const visibleSuggestions = useMemo(
    () => suggestions.filter((s) => s.match_bucket === activeBucket),
    [suggestions, activeBucket],
  )

  const bulkAcceptCurrent = () => {
    if (!visibleSuggestions.length) return
    if (!window.confirm(`Accept all ${visibleSuggestions.length} ${bucketLabels[activeBucket] || activeBucket} suggestions?`)) return
    router.post('/investment_suggestions/accept_all', { ids: visibleSuggestions.map((s) => s.id) })
  }

  return (
    <DashboardLayout title="Investment suggestions">
      <div className="max-w-5xl mx-auto">
        <div className="flex flex-wrap items-center justify-between gap-4 mb-6">
          <div>
            <h1 className="text-2xl font-bold text-slate-100">Review bank detections</h1>
            <p className="text-slate-400 text-sm mt-1">
              Bucketed by match confidence so you can bulk-accept the obvious ones and only manually review the rest.
            </p>
          </div>
          <Link href="/investments" className="text-violet-400 hover:underline text-sm font-medium">
            ← Portfolio
          </Link>
        </div>

        {/* Tabs */}
        <div className="mb-6 flex flex-wrap gap-2 border-b border-white/10">
          {BUCKET_ORDER.map((b) => {
            const count = buckets[b] || 0
            const isActive = activeBucket === b
            return (
              <button
                key={b}
                type="button"
                onClick={() => setActiveBucket(b)}
                disabled={count === 0}
                className={`px-4 py-2 -mb-px border-b-2 text-sm font-medium transition-colors ${
                  isActive
                    ? 'border-violet-500 text-violet-300'
                    : count === 0
                      ? 'border-transparent text-slate-600 cursor-not-allowed'
                      : 'border-transparent text-slate-400 hover:text-slate-200'
                }`}
              >
                {bucketLabels[b] || b} <span className="text-xs">({count})</span>
              </button>
            )
          })}
        </div>

        {total === 0 ? (
          <div className="sl-card rounded-2xl p-10 text-center border border-white/10">
            <p className="text-slate-400 mb-4">No pending suggestions. Upload more bank statements to detect investment-related transactions.</p>
            <button
              type="button"
              onClick={() => router.post('/investments/rescan')}
              className="px-4 py-2 border border-white/10 text-slate-200 text-sm font-medium rounded-lg hover:bg-white/5"
            >
              Re-scan transactions
            </button>
          </div>
        ) : (
          <>
            <div className={`mb-4 p-3 rounded-lg border text-sm ${BUCKET_BADGE_CLASSES[activeBucket]}`}>
              {BUCKET_DESCRIPTIONS[activeBucket]}
            </div>

            <div className="mb-4 flex flex-wrap gap-2">
              {visibleSuggestions.length > 1 && (
                <button
                  type="button"
                  onClick={bulkAcceptCurrent}
                  className="sl-btn-primary"
                >
                  Accept all {visibleSuggestions.length} in this bucket
                </button>
              )}
              <button
                type="button"
                onClick={() => router.post('/investments/rescan')}
                className="px-4 py-2 border border-white/10 text-slate-200 text-sm font-medium rounded-lg hover:bg-white/5"
                title="Re-evaluate all bank transactions against the latest detection rules"
              >
                Re-scan transactions
              </button>
            </div>

            {visibleSuggestions.length === 0 ? (
              <div className="sl-card rounded-2xl p-10 text-center border border-white/10">
                <p className="text-slate-400">No suggestions in this bucket — pick another tab above.</p>
              </div>
            ) : (
              <div className="space-y-3">
                {visibleSuggestions.map((s) => (
                  <SuggestionCard key={s.id} suggestion={s} />
                ))}
              </div>
            )}
          </>
        )}
      </div>
    </DashboardLayout>
  )
}

function SuggestionCard({ suggestion: s }) {
  const confidencePct = Math.round((s.confidence || 0) * 100)
  return (
    <div className="sl-card border border-white/10 p-5 shadow-sm flex flex-wrap justify-between gap-4">
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2 flex-wrap mb-2">
          <span className={`px-2 py-0.5 text-xs rounded-full border ${BUCKET_BADGE_CLASSES[s.match_bucket]}`}>
            {confidencePct}% confidence
          </span>
          {s.metadata?.folio_hint && (
            <span className="px-2 py-0.5 text-xs rounded-full bg-emerald-500/10 text-emerald-300 border border-emerald-500/30">
              Folio {s.metadata.folio_hint}
            </span>
          )}
        </div>
        <p className="font-medium text-slate-100">{s.transaction.description}</p>
        <p className="text-sm text-slate-500 mt-1">
          {s.transaction.date} · {s.transaction.bank_account} · {formatInr(s.transaction.amount)}
        </p>
        <p className="text-sm text-violet-300 mt-2">
          Suggested: {ASSET_LABELS[s.suggested_asset_class] || s.suggested_asset_class} ·{' '}
          {s.suggested_kind.replace(/_/g, ' ')} → {s.suggested_account_name}
        </p>
      </div>
      <div className="flex gap-2 items-start">
        <button
          type="button"
          onClick={() => router.post(`/investment_suggestions/${s.id}/accept`)}
          className="px-4 py-2 bg-green-600 text-white text-sm font-medium rounded-lg hover:bg-green-700"
        >
          Accept
        </button>
        <button
          type="button"
          onClick={() => router.post(`/investment_suggestions/${s.id}/reject`)}
          className="px-4 py-2 border border-white/10 text-slate-300 text-sm font-medium rounded-lg hover:bg-white/5"
        >
          Dismiss
        </button>
      </div>
    </div>
  )
}
