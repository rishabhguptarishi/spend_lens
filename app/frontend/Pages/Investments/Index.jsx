import { Link, router } from '@inertiajs/react'
import { useMemo, useState } from 'react'
import DashboardLayout from '../../Layouts/DashboardLayout'
import ReitDistributionSplit from './ReitDistributionSplit'

// Phase 4 §5.7 — /investments rendered as a list of INSTRUMENTS.
//
// Each row is one real-world security/account (Reliance ISIN, your PPF
// passbook, that one Mirae SIP). Position rollups are pre-computed
// server-side; this view just paints the rolled-up numbers and shows
// confirmed_by badges so the user can SEE which broker / CAS / tax
// doc backs each row.

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
  reit: 'REIT',
  invit: 'InvIT',
  p2p: 'P2P lending',
  fractional_re: 'Fractional real-estate',
  rsu: 'RSU',
  espp: 'ESPP',
  esop: 'ESOP',
  other: 'Other',
}

const SOURCE_LABELS = {
  bank_detect: 'Bank txn (detected)',
  bank_statement: 'Bank statement',
  broker_csv: 'Broker CSV',
  broker_import: 'Broker CSV',
  zerodha_csv: 'Zerodha',
  groww_csv: 'Groww',
  generic_csv: 'CSV',
  mf_cas: 'MF CAS',
  cdsl_cas: 'CDSL CAS',
  nsdl_cas: 'NSDL CAS',
  broker_pl: 'Broker P&L',
  mf_cg: 'MF capital gains',
  manual: 'Manual',
}

function badgeClassForSource(s) {
  switch (s) {
    case 'cdsl_cas':
    case 'nsdl_cas':
    case 'mf_cas':
    case 'broker_pl':
    case 'mf_cg':
      return 'sl-badge sl-badge-emerald'
    case 'broker_csv':
    case 'broker_import':
    case 'zerodha_csv':
    case 'groww_csv':
      return 'sl-badge sl-badge-violet'
    case 'bank_detect':
    case 'bank_statement':
      return 'sl-badge sl-badge-amber'
    case 'manual':
      return 'sl-badge sl-badge-slate'
    default:
      return 'sl-badge sl-badge-slate'
  }
}

function formatInr(n) {
  return `₹${Number(n || 0).toLocaleString('en-IN', { maximumFractionDigits: 2 })}`
}

function formatPct(n) {
  if (n === null || n === undefined) return '—'
  const sign = n > 0 ? '+' : ''
  return `${sign}${n.toFixed(2)}%`
}

export default function InvestmentsIndex({
  financial_year_start: fy,
  financial_year_label: fyLabel,
  years = [],
  instruments = [],
  summary = {},
  pending_suggestions_count: pendingCount = 0,
  accounts = [],
}) {
  const byClass = summary.by_asset_class || {}
  const [filterClass, setFilterClass] = useState('all')
  const [expanded, setExpanded] = useState({})

  const filteredInstruments = useMemo(() => {
    if (filterClass === 'all') return instruments
    return instruments.filter((i) => i.asset_class === filterClass)
  }, [instruments, filterClass])

  const unrealizedGain = Number(summary.unrealized_gain || 0)
  const unrealizedClass = unrealizedGain >= 0 ? 'text-emerald-400' : 'text-red-400'

  return (
    <DashboardLayout title="Investments">
      <div className="max-w-6xl mx-auto">
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
                className="sl-select"
              >
                {years.map((y) => (
                  <option key={y} value={y}>
                    FY {y}-{String((y + 1) % 100).padStart(2, '0')}
                  </option>
                ))}
              </select>
            )}
            <Link href="/investments/import" className="px-4 py-2 rounded-lg border border-white/10 text-slate-300 font-medium hover:bg-white/5">
              Import
            </Link>
            <Link href="/investments/activity" className="px-4 py-2 rounded-lg border border-white/10 text-slate-300 font-medium hover:bg-white/5">
              Activity
            </Link>
            <button
              type="button"
              onClick={() => router.post('/investments/rescan')}
              className="px-4 py-2 rounded-lg border border-white/10 text-slate-300 font-medium hover:bg-white/5"
              title="Re-evaluate every bank transaction against the latest detection rules"
            >
              Re-scan bank txns
            </button>
            <Link href="/investment_holdings/new" className="sl-btn-primary">
              Add holding
            </Link>
          </div>
        </div>

        {pendingCount > 0 && (
          <div className="mb-6 rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 flex flex-wrap items-center justify-between gap-3">
            <p className="text-amber-100">
              <strong>{pendingCount}</strong> bank transaction{pendingCount !== 1 ? 's' : ''} look like investments — review and add to your portfolio.
            </p>
            <Link href="/investments/suggestions" className="px-4 py-2 bg-amber-600 text-white font-medium rounded-lg hover:bg-amber-700">
              Review suggestions
            </Link>
          </div>
        )}

        {/* Phase 4 §5.7 row 1 — cost basis vs current value at a glance */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4 mb-8">
          <div className="sl-card rounded-2xl p-5 shadow-sm border border-white/10">
            <p className="text-xs font-medium text-slate-500 uppercase">Invested (cost)</p>
            <p className="text-xl font-bold text-slate-100 mt-1">{formatInr(summary.total_invested)}</p>
          </div>
          <div className="sl-card rounded-2xl p-5 shadow-sm border border-white/10">
            <p className="text-xs font-medium text-slate-500 uppercase">Current value</p>
            <p className="text-xl font-bold text-violet-400 mt-1">{formatInr(summary.total_current_value)}</p>
            <p className="text-xs text-slate-500 mt-1">{summary.nav_priced_count || 0} of {summary.instrument_count || 0} priced with live NAV</p>
          </div>
          <div className="sl-card rounded-2xl p-5 shadow-sm border border-white/10">
            <p className="text-xs font-medium text-slate-500 uppercase">Unrealized P&amp;L</p>
            <p className={`text-xl font-bold mt-1 ${unrealizedClass}`}>{formatInr(unrealizedGain)}</p>
          </div>
          <div className="sl-card rounded-2xl p-5 shadow-sm border border-white/10">
            <p className="text-xs font-medium text-slate-500 uppercase">FY contributions</p>
            <p className="text-xl font-bold text-emerald-400 mt-1">{formatInr(summary.fy_contributions)}</p>
          </div>
          <div className="sl-card rounded-2xl p-5 shadow-sm border border-white/10">
            <p className="text-xs font-medium text-slate-500 uppercase">FY sells / maturity</p>
            <p className="text-xl font-bold text-red-400 mt-1">{formatInr(summary.fy_sells)}</p>
          </div>
        </div>

        {Object.keys(byClass).length > 0 && (
          <div className="mb-8">
            <div className="flex flex-wrap items-center gap-2">
              <button
                onClick={() => setFilterClass('all')}
                className={`px-3 py-1.5 rounded-full text-sm font-medium ${filterClass === 'all' ? 'bg-violet-600 text-white' : 'bg-white/10 text-slate-300 hover:bg-white/20'}`}
              >
                All ({instruments.length})
              </button>
              {Object.entries(byClass).map(([cls, count]) => (
                <button
                  key={cls}
                  onClick={() => setFilterClass(cls)}
                  className={`px-3 py-1.5 rounded-full text-sm font-medium ${filterClass === cls ? 'bg-violet-600 text-white' : 'bg-white/10 text-slate-300 hover:bg-white/20'}`}
                >
                  {ASSET_LABELS[cls] || cls}: {count}
                </button>
              ))}
            </div>
          </div>
        )}

        <div className="flex justify-between items-center mb-4">
          <h2 className="text-lg font-semibold text-slate-100">Instruments</h2>
          <Link href="/investment_accounts/new" className="text-sm text-violet-400 hover:underline">
            Add account
          </Link>
        </div>

        {filteredInstruments.length > 0 ? (
          <div className="sl-card rounded-2xl shadow-sm border border-white/10 overflow-hidden">
            <table className="min-w-full">
              <thead className="bg-white/5">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium text-slate-500 uppercase">Instrument</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-slate-500 uppercase">Type</th>
                  <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Cost</th>
                  <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">Current</th>
                  <th className="px-4 py-3 text-right text-xs font-medium text-slate-500 uppercase">P&amp;L</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-slate-500 uppercase">Sources</th>
                  <th className="px-4 py-3" />
                </tr>
              </thead>
              <tbody className="divide-y divide-white/10">
                {filteredInstruments.map((i) => {
                  const isReit = ['reit', 'invit'].includes(i.asset_class)
                  const hasCustodianBreakdown = (i.custodians?.length || 0) > 1
                  const expandedKey = i.identity_key
                  const isExpanded = !!expanded[expandedKey]
                  const cost = Number(i.cost_basis || 0)
                  const current = i.current_value != null ? Number(i.current_value) : null
                  const pnl = current !== null ? current - cost : null
                  const pnlPct = current !== null && cost > 0 ? ((current - cost) / cost) * 100 : null
                  const pnlClass = pnl === null ? 'text-slate-400' : pnl >= 0 ? 'text-emerald-400' : 'text-red-400'

                  return (
                    <>
                      <tr key={i.identity_key} className="hover:bg-white/5">
                        <td className="px-4 py-3">
                          <div className="font-medium text-slate-100">{i.name}</div>
                          {i.folio && <div className="text-xs text-slate-500">{i.folio}</div>}
                          {i.symbol && !i.folio && <div className="text-xs text-slate-500">{i.symbol}</div>}
                        </td>
                        <td className="px-4 py-3 text-slate-400 text-sm">{ASSET_LABELS[i.asset_class] || i.asset_class}</td>
                        <td className="px-4 py-3 text-right text-slate-300">{formatInr(cost)}</td>
                        <td className="px-4 py-3 text-right">
                          {current !== null ? (
                            <>
                              <div className="text-slate-100 font-medium">{formatInr(current)}</div>
                              {i.nav && <div className="text-xs text-slate-500">NAV {i.nav.toFixed(2)}{i.nav_as_of ? ` · ${i.nav_as_of}` : ''}</div>}
                            </>
                          ) : (
                            <span className="text-slate-500 text-xs">live NAV unavailable</span>
                          )}
                        </td>
                        <td className={`px-4 py-3 text-right font-medium ${pnlClass}`}>
                          {pnl !== null ? formatInr(pnl) : '—'}
                          {pnlPct !== null && <div className="text-xs">{formatPct(pnlPct)}</div>}
                        </td>
                        <td className="px-4 py-3">
                          <div className="flex flex-wrap gap-1">
                            {(i.confirmed_by || []).slice(0, 4).map((src) => (
                              <span key={src} className={badgeClassForSource(src)}>{SOURCE_LABELS[src] || src}</span>
                            ))}
                            {(i.confirmed_by?.length || 0) > 4 && (
                              <span className="sl-badge sl-badge-slate">+{i.confirmed_by.length - 4}</span>
                            )}
                          </div>
                        </td>
                        <td className="px-4 py-3 text-right whitespace-nowrap">
                          {(hasCustodianBreakdown || isReit) && (
                            <button
                              onClick={() => setExpanded((p) => ({ ...p, [expandedKey]: !p[expandedKey] }))}
                              className="text-xs text-violet-400 hover:underline"
                            >
                              {isExpanded ? 'Hide' : 'Details'}
                            </button>
                          )}
                        </td>
                      </tr>
                      {isExpanded && (
                        <tr key={`${expandedKey}-detail`} className="bg-white/[0.02]">
                          <td colSpan={7} className="px-4 py-4">
                            {hasCustodianBreakdown && (
                              <div className="mb-4">
                                <p className="text-xs font-medium text-slate-500 uppercase mb-2">By custodian</p>
                                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                                  {i.custodians.map((c, idx) => (
                                    <div key={`${c.name}-${idx}`} className="border border-white/10 rounded-lg p-3">
                                      <p className="font-medium text-slate-200">{c.name}</p>
                                      <p className="text-xs text-slate-500 mt-1">Cost: {formatInr(c.cost_basis)}</p>
                                      {c.current_value != null && <p className="text-xs text-slate-500">Current: {formatInr(c.current_value)}</p>}
                                      {c.units > 0 && <p className="text-xs text-slate-500">Units: {Number(c.units).toLocaleString('en-IN')}</p>}
                                    </div>
                                  ))}
                                </div>
                              </div>
                            )}
                            {isReit && (
                              <ReitDistributionSplit instrument={i} />
                            )}
                          </td>
                        </tr>
                      )}
                    </>
                  )
                })}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="sl-card rounded-2xl p-10 text-center border border-white/10">
            <p className="text-slate-400 mb-4">No instruments match this filter.</p>
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
          Source badges show every channel that confirmed each instrument. Cost basis is canonical; current values use live NAV from mfapi.in (cached 12 h) and fall back to cost when NAV is unavailable.
        </p>
      </div>
    </DashboardLayout>
  )
}
