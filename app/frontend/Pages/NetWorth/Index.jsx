import { Link, router } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

// Phase 4 §5.7 row 4 — net worth surfaced from materialized positions
// (with NAV when available) instead of summing holdings cost basis.
// The "Live NAV" badge tells the user exactly how many positions are
// at market vs at cost.

const ASSET_LABELS = {
  mutual_fund: 'Mutual funds',
  stock: 'Stocks',
  bond: 'Bonds',
  fd: 'Fixed deposits',
  rd: 'Recurring deposits',
  ppf: 'PPF',
  nps: 'NPS',
  epf: 'EPF',
  crypto: 'Crypto',
  gold: 'Gold',
  real_estate: 'Real estate',
  reit: 'REIT',
  invit: 'InvIT',
  p2p: 'P2P lending',
  fractional_re: 'Fractional real-estate',
  rsu: 'RSU',
  espp: 'ESPP',
  esop: 'ESOP',
  other: 'Other',
}

function formatInr(n) {
  return `₹${Number(n || 0).toLocaleString('en-IN', { maximumFractionDigits: 2 })}`
}

export default function NetWorthIndex({
  total_invested = 0,
  total_current_value = 0,
  unrealized_gain = 0,
  total_bank = 0,
  net_worth_approx = 0,
  net_worth_cost_basis = 0,
  bank_estimates = [],
  by_asset_class = {},
  by_asset_class_current = {},
  positions = [],
  disclaimer = '',
  nav_priced_count = 0,
  position_count = 0,
}) {
  const unrealizedClass = unrealized_gain >= 0 ? 'text-emerald-400' : 'text-red-400'

  return (
    <DashboardLayout title="Net worth">
      <div className="max-w-5xl mx-auto">
        <div className="flex flex-wrap items-center justify-between gap-3 mb-2">
          <h1 className="text-2xl font-bold text-slate-100">Net worth</h1>
          <button
            type="button"
            onClick={() => router.post('/net_worth/refresh_nav')}
            className="px-3 py-1.5 text-sm rounded-lg border border-white/10 text-slate-300 hover:bg-white/5"
            title="Re-fetch live NAVs from mfapi.in"
          >
            ↻ Refresh NAV
          </button>
        </div>
        <p className="text-slate-400 text-sm mb-6">{disclaimer}</p>

        <div className="grid grid-cols-1 sm:grid-cols-4 gap-4 mb-8">
          <div className="sl-card p-5 rounded-2xl border border-white/10">
            <p className="text-xs text-slate-500 uppercase">Investments (cost)</p>
            <p className="text-2xl font-bold text-slate-100 mt-1">{formatInr(total_invested)}</p>
          </div>
          <div className="sl-card p-5 rounded-2xl border border-white/10">
            <p className="text-xs text-slate-500 uppercase">Investments (current)</p>
            <p className="text-2xl font-bold text-violet-400 mt-1">{formatInr(total_current_value)}</p>
            <p className="text-xs text-slate-500 mt-1">
              {nav_priced_count} of {position_count} priced with live NAV
            </p>
          </div>
          <div className="sl-card p-5 rounded-2xl border border-white/10">
            <p className="text-xs text-slate-500 uppercase">Unrealized P&amp;L</p>
            <p className={`text-2xl font-bold ${unrealizedClass} mt-1`}>{formatInr(unrealized_gain)}</p>
          </div>
          <div className="sl-card p-5 rounded-2xl border border-white/10">
            <p className="text-xs text-slate-500 uppercase">Banks (est.)</p>
            <p className="text-2xl font-bold text-slate-100 mt-1">{formatInr(total_bank)}</p>
          </div>
        </div>

        <div className="sl-card p-6 rounded-2xl border border-emerald-500/30 bg-emerald-500/5 mb-8">
          <div className="flex flex-wrap items-baseline justify-between gap-3">
            <div>
              <p className="text-xs text-emerald-200/70 uppercase">Total net worth (approximate)</p>
              <p className="text-3xl font-bold text-emerald-300 mt-1">{formatInr(net_worth_approx)}</p>
              <p className="text-xs text-slate-400 mt-1">
                At cost basis: {formatInr(net_worth_cost_basis)}
              </p>
            </div>
          </div>
        </div>

        <h2 className="text-lg font-semibold mb-3 text-slate-100">Bank accounts</h2>
        <div className="space-y-2 mb-8">
          {bank_estimates.map((b) => (
            <div key={b.id} className="flex justify-between sl-card px-4 py-3 rounded-lg border border-white/10">
              <span className="text-slate-200">{b.name}</span>
              <span className="font-medium">{formatInr(b.estimated_balance)}</span>
            </div>
          ))}
          {bank_estimates.length === 0 && (
            <p className="text-sm text-slate-500">No bank statements uploaded yet.</p>
          )}
        </div>

        <div className="flex justify-between items-center mb-3">
          <h2 className="text-lg font-semibold text-slate-100">Holdings by asset class</h2>
          <Link href="/investments" className="text-sm text-violet-400 hover:underline">
            Portfolio detail →
          </Link>
        </div>
        <div className="space-y-2 mb-8">
          {Object.entries(by_asset_class).map(([cls, cost]) => {
            const current = by_asset_class_current[cls] ?? cost
            const cls_gain = Number(current) - Number(cost)
            const gainClass = cls_gain >= 0 ? 'text-emerald-400' : 'text-red-400'
            return (
              <div key={cls} className="grid grid-cols-1 sm:grid-cols-4 gap-2 sl-card px-4 py-3 rounded-lg border border-white/10">
                <span className="text-slate-200 font-medium">{ASSET_LABELS[cls] || cls}</span>
                <span className="text-sm text-slate-400 text-right sm:text-left">Cost: {formatInr(cost)}</span>
                <span className="text-sm text-slate-100 text-right sm:text-left">Current: {formatInr(current)}</span>
                <span className={`text-sm font-medium text-right ${gainClass}`}>{cls_gain >= 0 ? '+' : ''}{formatInr(cls_gain)}</span>
              </div>
            )
          })}
          {Object.keys(by_asset_class).length === 0 && (
            <p className="text-sm text-slate-500">No investment positions yet. <Link href="/investment_holdings/new" className="text-violet-400 hover:underline">Add a holding</Link> or upload a statement to get started.</p>
          )}
        </div>

        {positions.length > 0 && (
          <details className="sl-card p-5 rounded-2xl border border-white/10">
            <summary className="font-semibold text-slate-200 cursor-pointer">Top positions (by current value)</summary>
            <table className="mt-3 w-full text-sm">
              <thead>
                <tr className="text-slate-500 text-xs uppercase">
                  <th className="text-left py-1">Holding</th>
                  <th className="text-left py-1">Custodian</th>
                  <th className="text-right py-1">Cost</th>
                  <th className="text-right py-1">Current</th>
                  <th className="text-right py-1">Return</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/5">
                {[...positions]
                  .sort((a, b) => (b.current_value ?? b.cost_basis ?? 0) - (a.current_value ?? a.cost_basis ?? 0))
                  .slice(0, 25)
                  .map((p) => {
                    const ret = p.unrealized_return_pct
                    const retClass = ret == null ? 'text-slate-400' : ret >= 0 ? 'text-emerald-400' : 'text-red-400'
                    return (
                      <tr key={p.id} className="text-slate-300">
                        <td className="py-2">
                          <div>{p.name}</div>
                          <div className="text-xs text-slate-500">{ASSET_LABELS[p.asset_class] || p.asset_class}</div>
                        </td>
                        <td className="py-2 text-sm text-slate-400">{p.custodian}</td>
                        <td className="text-right py-2">{formatInr(p.cost_basis)}</td>
                        <td className="text-right py-2">
                          {p.current_value != null ? formatInr(p.current_value) : <span className="text-xs text-slate-500">at cost</span>}
                        </td>
                        <td className={`text-right py-2 ${retClass}`}>
                          {ret != null ? `${ret >= 0 ? '+' : ''}${ret.toFixed(2)}%` : '—'}
                        </td>
                      </tr>
                    )
                  })}
              </tbody>
            </table>
          </details>
        )}

        <p className="mt-6 text-xs text-slate-500">
          NAV cache: 12-hour TTL from <a href="https://api.mfapi.in" className="text-violet-400 hover:underline" rel="noreferrer" target="_blank">mfapi.in</a> (free AMFI proxy). Stocks/REIT/InvIT show cost basis until we wire NSE/BSE price feeds.
        </p>
      </div>
    </DashboardLayout>
  )
}
