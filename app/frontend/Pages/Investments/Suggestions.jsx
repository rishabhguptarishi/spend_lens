import { Link, router } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

const ASSET_LABELS = {
  mutual_fund: 'Mutual fund',
  stock: 'Stock',
  bond: 'Bond',
  fd: 'FD',
  rd: 'RD',
  nps: 'NPS',
  ppf: 'PPF',
  crypto: 'Crypto',
  other: 'Other',
}

function formatInr(n) {
  return `₹${Number(n || 0).toLocaleString('en-IN')}`
}

export default function InvestmentsSuggestions({ suggestions = [] }) {
  return (
    <DashboardLayout title="Investment suggestions">
      <div className="max-w-4xl mx-auto">
        <div className="flex flex-wrap items-center justify-between gap-4 mb-6">
          <div>
            <h1 className="text-2xl font-bold text-slate-100">Review bank detections</h1>
            <p className="text-slate-400 text-sm mt-1">
              These transactions from your statements may be investments or investment income.
            </p>
          </div>
          <Link href="/investments" className="text-violet-400 hover:underline text-sm font-medium">
            ← Portfolio
          </Link>
        </div>

        <div className="mb-4 flex flex-wrap gap-2">
          {suggestions.length > 1 && (
            <button
              type="button"
              onClick={() => router.post('/investment_suggestions/accept_all')}
              className="sl-btn-primary"
            >
              Accept all
            </button>
          )}
          {/*
            Re-scan re-evaluates every bank transaction against the
            current detection rules. Useful when new rules ship (e.g. for
            MOB-TD, FRSB, AMC SIPs) so historical statements get their
            investments picked up retroactively.
          */}
          <button
            type="button"
            onClick={() => router.post('/investments/rescan')}
            className="px-4 py-2 border border-white/10 text-slate-200 text-sm font-medium rounded-lg hover:bg-white/5"
            title="Re-evaluate all bank transactions against the latest detection rules"
          >
            Re-scan transactions
          </button>
        </div>

        {suggestions.length > 0 ? (
          <div className="space-y-4">
            {suggestions.map((s) => (
              <div
                key={s.id}
                className="sl-card border border-white/10 p-5 shadow-sm flex flex-wrap justify-between gap-4"
              >
                <div className="min-w-0 flex-1">
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
            ))}
          </div>
        ) : (
          <div className="sl-card rounded-2xl p-10 text-center border border-white/10">
            <p className="text-slate-400">No pending suggestions. Upload more bank statements to detect investment-related transactions.</p>
          </div>
        )}
      </div>
    </DashboardLayout>
  )
}
