import { Link, router } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

const ASSET_LABELS = {
  mutual_fund: 'Mutual funds',
  stock: 'Stocks',
  bond: 'Bonds',
  fd: 'Fixed deposit',
  rd: 'Recurring deposit',
  ppf: 'PPF',
  nps: 'NPS',
  epf: 'EPF',
  crypto: 'Crypto',
  gold: 'Gold',
  real_estate: 'Real estate',
  other: 'Other',
}

function formatInr(n) {
  return `₹${Number(n || 0).toLocaleString('en-IN')}`
}

export default function InvestmentsIndex({
  financial_year_start: fy,
  financial_year_label: fyLabel,
  years = [],
  holdings = [],
  summary = {},
  pending_suggestions_count: pendingCount = 0,
  accounts = [],
}) {
  const byClass = summary.by_asset_class || {}

  return (
    <DashboardLayout title="Investments">
      <div className="max-w-5xl mx-auto">
        <div className="flex flex-wrap items-center justify-between gap-4 mb-6">
          <div>
            <h1 className="text-2xl font-bold text-slate-100">Portfolio</h1>
            <p className="text-slate-400 text-sm mt-1">FY {fyLabel} (Apr–Mar)</p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            {years.length > 0 && (
              <select
                value={fy}
                onChange={(e) => router.get('/investments', { fy: e.target.value })}
                className="px-3 py-2 rounded-lg border border-white/10 focus:ring-2 focus:ring-violet-500"
              >
                {years.map((y) => (
                  <option key={y} value={y}>
                    FY {y}-{String((y + 1) % 100).padStart(2, '0')}
                  </option>
                ))}
              </select>
            )}
            <Link
              href="/investments/import"
              className="px-4 py-2 rounded-lg border border-white/10 text-slate-300 font-medium hover:bg-white/5"
            >
              Import
            </Link>
            <Link
              href="/investments/activity"
              className="px-4 py-2 rounded-lg border border-white/10 text-slate-300 font-medium hover:bg-white/5"
            >
              Activity
            </Link>
            {/*
              Re-scans the user's bank-transaction history against the
              latest InvestmentDetectionService rules. Always reachable
              from the portfolio page so users don't have to navigate to
              Suggestions just to discover this exists when their
              pending count is currently zero.
            */}
            <button
              type="button"
              onClick={() => router.post('/investments/rescan')}
              className="px-4 py-2 rounded-lg border border-white/10 text-slate-300 font-medium hover:bg-white/5"
              title="Re-evaluate every bank transaction against the latest detection rules (MOB-TD, FRSB, AMC SIPs, …)"
            >
              Re-scan bank txns
            </button>
            <Link
              href="/investment_holdings/new"
              className="sl-btn-primary"
            >
              Add holding
            </Link>
          </div>
        </div>

        {pendingCount > 0 ? (
          <div className="mb-6 rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 flex flex-wrap items-center justify-between gap-3">
            <p className="text-amber-100">
              <strong>{pendingCount}</strong> bank transaction{pendingCount !== 1 ? 's' : ''} look like investments — review and add to your portfolio.
            </p>
            <Link
              href="/investments/suggestions"
              className="px-4 py-2 bg-amber-600 text-white font-medium rounded-lg hover:bg-amber-700"
            >
              Review suggestions
            </Link>
          </div>
        ) : (
          <div className="mb-6 rounded-xl border border-white/10 bg-white/5 p-4 flex flex-wrap items-center justify-between gap-3">
            <p className="text-slate-300 text-sm">
              Don't see your SIPs / FDs / RBI bonds here? Click <strong>Re-scan bank txns</strong> above to evaluate your full bank history against the latest detection rules (MOB-TD, FRSB, MIRAE / Canara Robeco SIPs, AXISDIRECT, sweep transfers, etc.).
            </p>
            <Link
              href="/investments/suggestions"
              className="text-violet-400 hover:underline text-sm font-medium whitespace-nowrap"
            >
              View suggestions →
            </Link>
          </div>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          <div className="sl-card rounded-2xl p-5 shadow-sm border border-white/10">
            <p className="text-xs font-medium text-slate-500 uppercase">Total invested (cost)</p>
            <p className="text-xl font-bold text-slate-100 mt-1">{formatInr(summary.total_invested)}</p>
          </div>
          <div className="sl-card rounded-2xl p-5 shadow-sm border border-white/10">
            <p className="text-xs font-medium text-slate-500 uppercase">Holdings</p>
            <p className="text-xl font-bold text-slate-100 mt-1">{summary.holdings_count || 0}</p>
          </div>
          <div className="sl-card rounded-2xl p-5 shadow-sm border border-white/10">
            <p className="text-xs font-medium text-slate-500 uppercase">FY contributions</p>
            <p className="text-xl font-bold text-violet-400 mt-1">{formatInr(summary.fy_contributions)}</p>
          </div>
          <div className="sl-card rounded-2xl p-5 shadow-sm border border-white/10">
            <p className="text-xs font-medium text-slate-500 uppercase">FY sells / maturity</p>
            <p className="text-xl font-bold text-red-600 mt-1">{formatInr(summary.fy_sells)}</p>
          </div>
        </div>

        {Object.keys(byClass).length > 0 && (
          <div className="mb-8">
            <h2 className="text-lg font-semibold text-slate-100 mb-3">By asset type</h2>
            <div className="flex flex-wrap gap-2">
              {Object.entries(byClass).map(([cls, count]) => (
                <span
                  key={cls}
                  className="px-3 py-1.5 rounded-full bg-white/10 text-slate-300 text-sm font-medium"
                >
                  {ASSET_LABELS[cls] || cls}: {count}
                </span>
              ))}
            </div>
          </div>
        )}

        <div className="flex justify-between items-center mb-4">
          <h2 className="text-lg font-semibold text-slate-100">Holdings</h2>
          <Link href="/investment_accounts/new" className="text-sm text-violet-400 hover:underline">
            Add account
          </Link>
        </div>

        {holdings.length > 0 ? (
          <div className="sl-card rounded-2xl shadow-sm border border-white/10 overflow-hidden">
            <table className="min-w-full">
              <thead className="bg-white/5">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium text-slate-500 uppercase">Name</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-slate-500 uppercase">Type</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-slate-500 uppercase">Account</th>
                  <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Invested</th>
                  <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase" />
                </tr>
              </thead>
              <tbody className="divide-y divide-white/10">
                {holdings.map((h) => (
                  <tr key={h.id}>
                    <td className="px-4 py-3 text-slate-100">{h.name}</td>
                    <td className="px-4 py-3 text-slate-400 text-sm">{ASSET_LABELS[h.asset_class] || h.asset_class}</td>
                    <td className="px-4 py-3 text-slate-400 text-sm">{h.account}</td>
                    <td className="px-4 py-3 text-right font-medium">{formatInr(h.invested_amount)}</td>
                    <td className="px-4 py-3 text-right">
                      <Link href={`/investment_holdings/${h.id}/edit`} className="text-sm text-violet-400 hover:underline">
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
            <p className="text-slate-400 mb-4">No holdings yet. Add manually or review bank suggestions after uploading statements.</p>
            <div className="flex justify-center gap-3 flex-wrap">
              <Link href="/investment_holdings/new" className="px-4 py-2 sl-btn-primary">
                Add holding
              </Link>
              {pendingCount > 0 && (
                <Link href="/investments/suggestions" className="px-4 py-2 border border-white/10 rounded-lg font-medium text-slate-300">
                  Review bank suggestions
                </Link>
              )}
            </div>
          </div>
        )}

        {accounts.length > 0 && (
          <div className="mt-8">
            <h2 className="text-lg font-semibold text-slate-100 mb-3">Accounts</h2>
            <ul className="space-y-2">
              {accounts.map((a) => (
                <li key={a.id} className="flex justify-between items-center sl-card rounded-lg px-4 py-3 border border-white/10">
                  <span className="font-medium text-slate-100">{a.name}</span>
                  <Link href={`/investment_accounts/${a.id}/edit`} className="text-sm text-violet-400 hover:underline">
                    Edit
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        )}

        <p className="mt-8 text-xs text-slate-500">
          Holdings show cost basis only — no live NAV or XIRR. Import Zerodha, Groww, MF CAS, or generic CSV from Import.
        </p>
      </div>
    </DashboardLayout>
  )
}
