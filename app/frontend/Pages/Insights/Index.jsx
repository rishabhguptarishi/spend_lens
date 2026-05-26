import { Link, router } from '@inertiajs/react'
import { useMemo, useState } from 'react'
import DashboardLayout from '../../Layouts/DashboardLayout'
import DateRangePresets, { buildPresets } from '../../Components/DateRangePresets'

const fmtDate = (iso) => {
  if (!iso) return ''
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return iso
  return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' })
}

const fmtPresetDate = (d) => {
  const yyyy = d.getFullYear()
  const mm = String(d.getMonth() + 1).padStart(2, '0')
  const dd = String(d.getDate()).padStart(2, '0')
  return `${yyyy}-${mm}-${dd}`
}

export default function InsightsIndex({
  filter = 'month',
  month,
  year,
  start_date = '',
  end_date = '',
  months = [],
  years = [],
  period_expenses = 0,
  compare_expenses = 0,
  change_pct = 0,
  by_category = [],
  top_merchants = [],
  rewards_gap = {},
}) {
  const gaps = rewards_gap?.gaps || []
  const totalMissed = rewards_gap?.total_missed || 0
  const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']
  const monthsData = months?.length > 0 ? months : monthNames.map((name, i) => [name, i + 1])
  const yearsData = years?.length > 0 ? years : Array.from({ length: 6 }, (_, i) => new Date().getFullYear() - i)

  const [localFilter, setLocalFilter] = useState(filter)
  const [localMonth, setLocalMonth] = useState(month ?? new Date().getMonth() + 1)
  const [localYear, setLocalYear] = useState(year ?? new Date().getFullYear())
  const [localStart, setLocalStart] = useState(start_date || '')
  const [localEnd, setLocalEnd] = useState(end_date || '')

  const apply = () => {
    if (localFilter === 'range') {
      router.get('/insights', { filter: 'range', start_date: localStart, end_date: localEnd })
    } else {
      router.get('/insights', { filter: 'month', month: localMonth, year: localYear })
    }
  }

  const applyPreset = ({ start_date, end_date }) => {
    setLocalFilter('range')
    setLocalStart(start_date)
    setLocalEnd(end_date)
    router.get('/insights', { filter: 'range', start_date, end_date })
  }

  const periodLabel = useMemo(() => {
    if (filter === 'range' && start_date && end_date) {
      // If the range matches a known preset (e.g. "Previous FY"), surface its
      // friendly label instead of the raw ISO range.
      const preset = buildPresets().find(
        (p) => fmtPresetDate(p.start) === start_date && fmtPresetDate(p.end) === end_date
      )
      if (preset) return preset.label
      return `${fmtDate(start_date)} → ${fmtDate(end_date)}`
    }
    return monthsData.find(([, m]) => m === month)?.[0] || 'Selected period'
  }, [filter, start_date, end_date, month, monthsData])

  return (
    <DashboardLayout title="Spending Insights">
      <div className="max-w-4xl mx-auto">
        <h2 className="text-lg font-semibold text-slate-100 mb-6">Spending Insights</h2>

        <div className="sl-card rounded-2xl p-6 shadow-sm border border-white/10 mb-6 space-y-4">
          <h2 className="text-sm font-medium text-slate-500 uppercase">Filter</h2>
          <DateRangePresets
            onApply={applyPreset}
            currentStart={filter === 'range' ? start_date : ''}
            currentEnd={filter === 'range' ? end_date : ''}
          />
          <div className="flex flex-wrap gap-4 items-end">
            <div className="flex gap-2">
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="radio"
                  name="filter"
                  checked={localFilter === 'month'}
                  onChange={() => setLocalFilter('month')}
                  className="text-violet-400"
                />
                <span className="text-sm text-slate-300">Month</span>
              </label>
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="radio"
                  name="filter"
                  checked={localFilter === 'range'}
                  onChange={() => setLocalFilter('range')}
                  className="text-violet-400"
                />
                <span className="text-sm text-slate-300">Date range</span>
              </label>
            </div>
            {localFilter === 'month' ? (
              <>
                <select
                  value={localMonth}
                  onChange={(e) => setLocalMonth(Number(e.target.value))}
                  className="px-3 py-2 rounded-lg border border-white/10 text-sm"
                >
                  {monthsData.map(([name, m]) => (
                    <option key={m} value={m}>{name}</option>
                  ))}
                </select>
                <select
                  value={localYear}
                  onChange={(e) => setLocalYear(Number(e.target.value))}
                  className="px-3 py-2 rounded-lg border border-white/10 text-sm"
                >
                  {yearsData.map((y) => (
                    <option key={y} value={y}>{y}</option>
                  ))}
                </select>
              </>
            ) : (
              <>
                <input
                  type="date"
                  value={localStart}
                  onChange={(e) => setLocalStart(e.target.value)}
                  className="px-3 py-2 rounded-lg border border-white/10 text-sm"
                />
                <span className="text-slate-400">to</span>
                <input
                  type="date"
                  value={localEnd}
                  onChange={(e) => setLocalEnd(e.target.value)}
                  className="px-3 py-2 rounded-lg border border-white/10 text-sm"
                />
              </>
            )}
            <button
              type="button"
              onClick={apply}
              className="sl-btn-primary text-sm"
            >
              Apply
            </button>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
          <div className="sl-card rounded-2xl p-6 shadow-sm border border-white/10">
            <p className="text-sm text-slate-500">{periodLabel}</p>
            <p className="text-3xl font-bold text-slate-100 mt-1">
              ₹{period_expenses.toLocaleString('en-IN')}
            </p>
          </div>
          <div className="sl-card rounded-2xl p-6 shadow-sm border border-white/10">
            <p className="text-sm text-slate-500">vs previous period</p>
            <p className={`text-2xl font-bold mt-1 ${change_pct >= 0 ? 'text-red-600' : 'text-violet-400'}`}>
              {change_pct >= 0 ? '+' : ''}{change_pct}%
            </p>
          </div>
        </div>

        {(gaps.length > 0 || rewards_gap?.message) && (
          <div className="sl-card rounded-2xl p-6 shadow-sm border border-amber-100 mb-8">
            <div className="flex items-start justify-between gap-4 mb-4">
              <div>
                <h2 className="text-lg font-semibold text-slate-100">Rewards gap (last 3 months)</h2>
                <p className="text-sm text-slate-400 mt-1">
                  Estimated rewards if you used your best card vs ~1% default earn rate.
                </p>
              </div>
              {totalMissed > 0 && (
                <div className="text-right shrink-0">
                  <p className="text-xs text-slate-500 uppercase">Possible missed</p>
                  <p className="text-2xl font-bold text-amber-600">₹{totalMissed.toLocaleString('en-IN')}</p>
                </div>
              )}
            </div>
            {rewards_gap?.message && (
              <p className="text-sm text-amber-700 mb-4">{rewards_gap.message}</p>
            )}
            {gaps.length > 0 && (
              <div className="space-y-3">
                {gaps.map((g) => (
                  <div key={g.category} className="flex flex-wrap items-center justify-between gap-2 py-3 border-b border-white/10 last:border-0">
                    <div>
                      <p className="font-medium text-slate-100">{g.category}</p>
                      <p className="text-sm text-slate-500">
                        Spent ₹{g.amount_spent?.toLocaleString('en-IN')} — use <strong>{g.best_card}</strong> ({g.best_rate})
                      </p>
                    </div>
                    <div className="text-right">
                      <p className="text-sm text-slate-500">Missed ~₹{g.missed_rewards?.toLocaleString('en-IN')}</p>
                      <p className="text-xs text-emerald-600">Could earn ₹{g.optimal_rewards?.toLocaleString('en-IN')}</p>
                    </div>
                  </div>
                ))}
              </div>
            )}
            <Link
              href="/credit_cards/suggestions"
              className="inline-block mt-4 text-sm font-medium text-amber-600 hover:text-amber-700"
            >
              View full rewards optimizer →
            </Link>
          </div>
        )}

        {by_category.length > 0 && (
          <div className="sl-card rounded-2xl p-6 shadow-sm border border-white/10 mb-8">
            <h2 className="text-lg font-semibold text-slate-100 mb-4">By category</h2>
            <div className="space-y-3">
              {by_category.map((c) => (
                <div key={c.name} className="flex items-center gap-4">
                  <div className="w-3 h-3 rounded-full" style={{ backgroundColor: c.color }} />
                  <span className="flex-1 text-slate-300">{c.name}</span>
                  <span className="font-medium text-slate-100">₹{c.amount.toLocaleString('en-IN')}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {top_merchants.length > 0 && (
          <div className="sl-card rounded-2xl p-6 shadow-sm border border-white/10">
            <h2 className="text-lg font-semibold text-slate-100 mb-4">Top merchants — {periodLabel}</h2>
            <div className="space-y-3">
              {top_merchants.map((m, i) => (
                <div key={i} className="flex justify-between">
                  <span className="text-slate-300">{m.merchant}</span>
                  <span className="font-medium text-slate-100">₹{m.amount.toLocaleString('en-IN')}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {by_category.length === 0 && top_merchants.length === 0 && (
          <div className="sl-card rounded-2xl p-12 text-center border border-white/10">
            <p className="text-slate-400">Upload statements to see spending insights.</p>
            <Link href="/upload" className="inline-block mt-4 text-violet-400 font-medium hover:underline">
              Upload Statement
            </Link>
          </div>
        )}
      </div>
    </DashboardLayout>
  )
}
