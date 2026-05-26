import { Link, router } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

const STATUS_STYLES = {
  match: 'text-emerald-300 bg-emerald-500/20',
  gap: 'text-red-300 bg-red-500/20',
  unverified: 'text-amber-200 bg-amber-500/10',
  no_data: 'text-slate-400 bg-white/5',
}

export default function ItrReconciliation({
  year,
  years = [],
  financial_year_label: fyLabel,
  rows = [],
  gaps_count = 0,
  match_count = 0,
  has_ais = false,
}) {
  return (
    <DashboardLayout title="AIS reconciliation">
      <div className="max-w-4xl mx-auto">
        <div className="flex flex-wrap justify-between gap-4 mb-6">
          <div>
            <Link href="/itr" className="text-sm text-violet-400 hover:underline">← ITR Assistant</Link>
            <h1 className="text-2xl font-bold text-slate-100 mt-2">AIS reconciliation</h1>
            <p className="text-slate-400 text-sm">FY {fyLabel}</p>
          </div>
          <select
            value={year}
            onChange={(e) => router.get('/itr/reconciliation', { year: e.target.value })}
            className="px-3 py-2 rounded-lg border border-white/10"
          >
            {years.map((y) => (
              <option key={y} value={y}>
                FY {y}-{String((y + 1) % 100).padStart(2, '0')}
              </option>
            ))}
          </select>
        </div>

        {!has_ais && (
          <p className="mb-4 sl-alert-warning text-sm">
            Upload AIS on the ITR page for full reconciliation. Showing bank + portfolio estimates.
          </p>
        )}

        <p className="text-sm text-slate-400 mb-4">
          {match_count} matched · {gaps_count} gaps
        </p>

        <div className="sl-card border overflow-hidden">
          <table className="min-w-full text-sm">
            <thead className="bg-white/5">
              <tr>
                <th className="px-4 py-3 text-left">Income type</th>
                <th className="px-4 py-3 text-right">AIS / Form 16</th>
                <th className="px-4 py-3 text-right">SpendLens</th>
                <th className="px-4 py-3 text-right">Diff</th>
                <th className="px-4 py-3 text-left">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {rows.map((r) => (
                <tr key={r.label}>
                  <td className="px-4 py-3 font-medium">{r.label}</td>
                  <td className="px-4 py-3 text-right">{r.ais_amount != null ? `₹${r.ais_amount.toLocaleString('en-IN')}` : '—'}</td>
                  <td className="px-4 py-3 text-right">₹{r.spendlens_amount.toLocaleString('en-IN')}</td>
                  <td className="px-4 py-3 text-right">{r.difference != null ? `₹${r.difference.toLocaleString('en-IN')}` : '—'}</td>
                  <td className="px-4 py-3">
                    <span className={`px-2 py-0.5 rounded text-xs font-medium ${STATUS_STYLES[r.status] || ''}`}>
                      {r.status}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="mt-4 text-xs text-slate-500">{rows[0]?.note}</p>
      </div>
    </DashboardLayout>
  )
}
