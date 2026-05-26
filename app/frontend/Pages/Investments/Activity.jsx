import { Link, router } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

const KIND_LABELS = {
  buy: 'Buy',
  sell: 'Sell',
  dividend: 'Dividend',
  interest: 'Interest',
  contribution: 'Contribution',
  sip: 'SIP',
  transfer_in: 'Transfer in',
  transfer_out: 'Transfer out',
  maturity: 'Maturity',
  fee: 'Fee',
  other: 'Other',
}

function formatInr(n) {
  return `₹${Number(n || 0).toLocaleString('en-IN')}`
}

export default function InvestmentsActivity({
  financial_year_start: fy,
  financial_year_label: fyLabel,
  years = [],
  transactions = [],
}) {
  return (
    <DashboardLayout title="Investment activity">
      <div className="max-w-5xl mx-auto">
        <div className="flex flex-wrap items-center justify-between gap-4 mb-6">
          <div>
            <h1 className="text-2xl font-bold text-slate-100">Activity</h1>
            <p className="text-slate-400 text-sm">FY {fyLabel}</p>
          </div>
          <div className="flex gap-2 flex-wrap">
            <Link href="/investments" className="px-4 py-2 rounded-lg border border-white/10 text-slate-300 font-medium">
              Portfolio
            </Link>
            {years.length > 0 && (
              <select
                value={fy}
                onChange={(e) => router.get('/investments/activity', { fy: e.target.value })}
                className="px-3 py-2 rounded-lg border border-white/10"
              >
                {years.map((y) => (
                  <option key={y} value={y}>
                    FY {y}-{String((y + 1) % 100).padStart(2, '0')}
                  </option>
                ))}
              </select>
            )}
            <Link
              href={`/investment_transactions/new?fy=${fy}`}
              className="sl-btn-primary"
            >
              Add activity
            </Link>
          </div>
        </div>

        {transactions.length > 0 ? (
          <div className="sl-card rounded-2xl shadow-sm border border-white/10 overflow-hidden">
            <table className="min-w-full">
              <thead className="bg-white/5">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium text-slate-500 uppercase">Date</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-slate-500 uppercase">Kind</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-slate-500 uppercase">Description</th>
                  <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Amount</th>
                  <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase" />
                </tr>
              </thead>
              <tbody className="divide-y divide-white/10">
                {transactions.map((t) => (
                  <tr key={t.id}>
                    <td className="px-4 py-3 text-slate-100 whitespace-nowrap">{t.date}</td>
                    <td className="px-4 py-3 text-sm text-slate-400">{KIND_LABELS[t.kind] || t.kind}</td>
                    <td className="px-4 py-3 text-slate-300 text-sm max-w-xs truncate">
                      {t.description || t.holding || '—'}
                      {t.source === 'bank_detect' && (
                        <span className="ml-1 text-xs text-amber-600">(bank)</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right font-medium">{formatInr(t.amount)}</td>
                    <td className="px-4 py-3 text-right">
                      <Link href={`/investment_transactions/${t.id}/edit`} className="text-sm text-violet-400 hover:underline">
                        Edit
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="sl-card rounded-2xl p-10 text-center border border-white/10">
            <p className="text-slate-400 mb-4">No investment activity for this financial year.</p>
            <Link
              href={`/investment_transactions/new?fy=${fy}`}
              className="inline-block px-4 py-2 sl-btn-primary"
            >
              Record activity
            </Link>
          </div>
        )}
      </div>
    </DashboardLayout>
  )
}
