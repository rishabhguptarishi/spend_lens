import { Link, router } from '@inertiajs/react'
import { useState, useEffect, useMemo } from 'react'
import {
  DocumentArrowUpIcon,
  CalendarDaysIcon,
  ExclamationTriangleIcon,
  AdjustmentsHorizontalIcon,
  ChevronUpIcon,
  ChevronDownIcon,
  ArrowPathIcon,
} from '@heroicons/react/24/outline'
import DashboardLayout from '../../Layouts/DashboardLayout'
import DateRangePresets from '../../Components/DateRangePresets'
import { WIDGET_RENDERERS } from './WidgetSections'

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']

const DEFAULT_WIDGET_ORDER = [
  'quick_actions',
  'alerts',
  'hero',
  'kpis',
  'daily_sparkline',
  'charts',
  'budget_vs_actual',
  'top_spend',
  'budgets_itr',
  'accounts',
  'transactions',
]

export default function DashboardIndex({
  bank_accounts = [],
  recent_transactions = [],
  spending_by_category = [],
  monthly_trend = [],
  metrics = {},
  widget_order = DEFAULT_WIDGET_ORDER,
  widget_catalog = [],
  month,
  year = new Date().getFullYear(),
  start_date,
  end_date,
  period_label = 'This Month',
  pending_investment_suggestions = 0,
}) {
  const [filterMode, setFilterMode] = useState(start_date ? 'range' : 'month')
  const [localMonth, setLocalMonth] = useState(month ?? new Date().getMonth() + 1)
  const [localYear, setLocalYear] = useState(year ?? new Date().getFullYear())
  const [localStart, setLocalStart] = useState(start_date || '')
  const [localEnd, setLocalEnd] = useState(end_date || '')
  const [customizeOpen, setCustomizeOpen] = useState(false)
  const [draftOrder, setDraftOrder] = useState(widget_order)

  useEffect(() => {
    setLocalMonth(month ?? new Date().getMonth() + 1)
    setLocalYear(year ?? new Date().getFullYear())
    setLocalStart(start_date || '')
    setLocalEnd(end_date || '')
    setFilterMode(start_date ? 'range' : 'month')
  }, [month, year, start_date, end_date])

  useEffect(() => {
    setDraftOrder(widget_order)
  }, [widget_order])

  const applyMonthFilter = () => router.get('/dashboard', { month: localMonth, year: localYear })
  const applyRangeFilter = () => {
    if (localStart && localEnd) router.get('/dashboard', { start_date: localStart, end_date: localEnd })
  }
  const applyPreset = ({ start_date, end_date }) => {
    setFilterMode('range')
    setLocalStart(start_date)
    setLocalEnd(end_date)
    router.get('/dashboard', { start_date, end_date })
  }

  const {
    income = 0,
    expenses = 0,
    net_flow = 0,
    savings_rate,
    income_change_pct,
    expenses_change_pct,
    transaction_count = 0,
    uncategorized_count = 0,
    recurring_count = 0,
    top_merchants = [],
    top_categories = [],
    budgets = [],
    budget_vs_actual = [],
    daily_spend = { points: [] },
    net_worth = {},
    itr = null,
    credit_cards_count = 0,
  } = metrics

  const hasData = transaction_count > 0 || bank_accounts.length > 0
  const overBudgets = budgets.filter((b) => b.remaining < 0)
  const maxCategoryAmount = top_categories[0]?.amount || 1

  const pendingReviewStatements = useMemo(() => {
    const out = []
    bank_accounts.forEach((acct) => {
      ;(acct.statements || []).forEach((s) => {
        if (s.status === 'pending_overlap_review') out.push({ ...s, bank_account: acct })
      })
    })
    return out
  }, [bank_accounts])

  const widgetCtx = useMemo(
    () => ({
      pending_investment_suggestions,
      uncategorized_count,
      overBudgets,
      recurring_count,
      net_flow,
      income,
      expenses,
      savings_rate,
      transaction_count,
      income_change_pct,
      expenses_change_pct,
      net_worth,
      spending_by_category,
      monthly_trend,
      period_label,
      top_merchants,
      top_categories,
      maxCategoryAmount,
      budgets,
      budget_vs_actual,
      daily_spend,
      itr,
      credit_cards_count,
      bank_accounts,
      recent_transactions,
    }),
    [
      pending_investment_suggestions,
      uncategorized_count,
      overBudgets,
      recurring_count,
      net_flow,
      income,
      expenses,
      savings_rate,
      transaction_count,
      income_change_pct,
      expenses_change_pct,
      net_worth,
      spending_by_category,
      monthly_trend,
      period_label,
      top_merchants,
      top_categories,
      maxCategoryAmount,
      budgets,
      budget_vs_actual,
      daily_spend,
      itr,
      credit_cards_count,
      bank_accounts,
      recent_transactions,
    ]
  )

  const catalogById = useMemo(() => {
    const map = {}
    widget_catalog.forEach((w) => {
      map[w.id] = w.label
    })
    return map
  }, [widget_catalog])

  const moveWidget = (id, direction) => {
    setDraftOrder((prev) => {
      const idx = prev.indexOf(id)
      if (idx < 0) return prev
      const next = [...prev]
      const swap = direction === 'up' ? idx - 1 : idx + 1
      if (swap < 0 || swap >= next.length) return prev
      ;[next[idx], next[swap]] = [next[swap], next[idx]]
      return next
    })
  }

  const saveLayout = () => {
    const query = { widgets: draftOrder }
    if (start_date && end_date) {
      query.start_date = start_date
      query.end_date = end_date
    } else if (month != null && year != null) {
      query.month = month
      query.year = year
    }
    router.patch('/dashboard/layout', query, { preserveScroll: true, onSuccess: () => setCustomizeOpen(false) })
  }

  const resetLayout = () => {
    setDraftOrder([...DEFAULT_WIDGET_ORDER])
  }

  const activeOrder = customizeOpen ? draftOrder : widget_order

  const greeting = () => {
    const h = new Date().getHours()
    if (h < 12) return 'Good morning'
    if (h < 17) return 'Good afternoon'
    return 'Good evening'
  }

  if (!hasData) {
    return (
      <DashboardLayout title="Dashboard">
        <div className="sl-empty max-w-lg mx-auto">
          <div className="mx-auto flex h-20 w-20 items-center justify-center rounded-full bg-violet-500/20 border border-violet-500/30">
            <DocumentArrowUpIcon className="h-10 w-10 text-violet-400" />
          </div>
          <h3 className="mt-6 text-xl font-semibold text-white">Welcome to SpendLens</h3>
          <p className="mt-2 text-slate-400">
            Upload a bank statement to see income, spending, budgets, and tax readiness in one place.
          </p>
          <Link href="/upload" className="mt-8 inline-flex items-center gap-2 sl-btn-primary px-8 py-3">
            <DocumentArrowUpIcon className="h-5 w-5" />
            Upload your first statement
          </Link>
        </div>
      </DashboardLayout>
    )
  }

  return (
    <DashboardLayout title="Dashboard">
      <div className="space-y-8">
        {pendingReviewStatements.length > 0 && (
          <div className="flex flex-col gap-3 rounded-2xl border border-amber-500/40 bg-amber-500/10 px-5 py-4 text-amber-100 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-start gap-3">
              <ExclamationTriangleIcon className="h-5 w-5 mt-0.5 shrink-0 text-amber-300" />
              <div>
                <p className="font-medium">
                  {pendingReviewStatements.length} statement{pendingReviewStatements.length === 1 ? '' : 's'} waiting on your decision
                </p>
                <p className="text-sm text-amber-100/80 mt-0.5">
                  We detected an overlap with existing data. Pick whether to replace, keep both, or cancel — parsing is paused until you choose.
                </p>
              </div>
            </div>
            <Link
              href={`/statements/${pendingReviewStatements[0].id}/overlap_review`}
              className="px-4 py-2 rounded-lg bg-amber-500/20 hover:bg-amber-500/30 border border-amber-500/40 text-amber-100 font-medium whitespace-nowrap"
            >
              Resolve {pendingReviewStatements.length > 1 ? '(start with oldest)' : ''}
            </Link>
          </div>
        )}

        <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <p className="text-sm text-slate-400">{greeting()}</p>
            <h2 className="text-2xl font-bold text-white tracking-tight">Financial overview</h2>
            <p className="text-slate-500 text-sm mt-1">{period_label}</p>
          </div>
          <div className="flex flex-wrap items-end gap-2">
            <button
              type="button"
              onClick={() => setCustomizeOpen((o) => !o)}
              className={`sl-btn-secondary py-2 ${customizeOpen ? 'border-violet-500/50 text-violet-200' : ''}`}
            >
              <AdjustmentsHorizontalIcon className="h-4 w-4" />
              {customizeOpen ? 'Done' : 'Customize'}
            </button>
            <div className="sl-card p-3 flex flex-col gap-3">
              <div className="flex flex-wrap items-end gap-3">
                <CalendarDaysIcon className="h-5 w-5 text-violet-400 shrink-0" />
                <label className="flex items-center gap-1.5 text-sm text-slate-300">
                  <input type="radio" checked={filterMode === 'month'} onChange={() => setFilterMode('month')} className="sl-checkbox" />
                  Month
                </label>
                <label className="flex items-center gap-1.5 text-sm text-slate-300">
                  <input type="radio" checked={filterMode === 'range'} onChange={() => setFilterMode('range')} className="sl-checkbox" />
                  Range
                </label>
                {filterMode === 'month' ? (
                  <>
                    <select value={localMonth} onChange={(e) => setLocalMonth(Number(e.target.value))} className="sl-select w-auto">
                      {MONTHS.map((m, i) => (
                        <option key={m} value={i + 1}>
                          {m}
                        </option>
                      ))}
                    </select>
                    <select value={localYear} onChange={(e) => setLocalYear(Number(e.target.value))} className="sl-select w-auto">
                      {[2026, 2025, 2024, 2023].map((y) => (
                        <option key={y} value={y}>
                          {y}
                        </option>
                      ))}
                    </select>
                    <button type="button" onClick={applyMonthFilter} className="sl-btn-primary py-2">
                      Apply
                    </button>
                  </>
                ) : (
                  <>
                    <input type="date" value={localStart} onChange={(e) => setLocalStart(e.target.value)} className="sl-select w-auto" />
                    <span className="text-slate-500 text-sm">to</span>
                    <input type="date" value={localEnd} onChange={(e) => setLocalEnd(e.target.value)} className="sl-select w-auto" />
                    <button type="button" onClick={applyRangeFilter} className="sl-btn-primary py-2">
                      Apply
                    </button>
                  </>
                )}
              </div>
              <DateRangePresets
                onApply={applyPreset}
                currentStart={filterMode === 'range' ? localStart : ''}
                currentEnd={filterMode === 'range' ? localEnd : ''}
              />
            </div>
          </div>
        </div>

        {customizeOpen && (
          <div className="sl-card p-5 border-violet-500/30">
            <div className="flex flex-wrap items-center justify-between gap-3 mb-4">
              <div>
                <h3 className="font-semibold text-white">Dashboard layout</h3>
                <p className="text-sm text-slate-400 mt-1">Reorder sections with the arrows. Changes apply to your account only.</p>
              </div>
              <div className="flex gap-2">
                <button type="button" onClick={resetLayout} className="sl-btn-secondary py-2 text-xs">
                  <ArrowPathIcon className="h-4 w-4" />
                  Reset default
                </button>
                <button type="button" onClick={saveLayout} className="sl-btn-primary py-2 text-xs">
                  Save layout
                </button>
              </div>
            </div>
            <ul className="space-y-2">
              {draftOrder.map((id, index) => (
                <li
                  key={id}
                  className="flex items-center justify-between gap-3 rounded-lg border border-white/10 bg-white/5 px-3 py-2"
                >
                  <span className="text-sm text-slate-200">
                    <span className="text-slate-500 mr-2 tabular-nums">{index + 1}.</span>
                    {catalogById[id] || id}
                  </span>
                  <div className="flex gap-1">
                    <button
                      type="button"
                      disabled={index === 0}
                      onClick={() => moveWidget(id, 'up')}
                      className="p-1.5 rounded-lg border border-white/10 text-slate-400 hover:bg-white/10 disabled:opacity-30"
                      aria-label="Move up"
                    >
                      <ChevronUpIcon className="h-4 w-4" />
                    </button>
                    <button
                      type="button"
                      disabled={index === draftOrder.length - 1}
                      onClick={() => moveWidget(id, 'down')}
                      className="p-1.5 rounded-lg border border-white/10 text-slate-400 hover:bg-white/10 disabled:opacity-30"
                      aria-label="Move down"
                    >
                      <ChevronDownIcon className="h-4 w-4" />
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        )}

        {activeOrder.map((widgetId) => {
          const render = WIDGET_RENDERERS[widgetId]
          if (!render) return null
          const content = render(widgetCtx)
          if (!content) return null
          return (
            <div key={widgetId} className={customizeOpen ? 'ring-1 ring-violet-500/30 rounded-2xl p-1' : ''}>
              {content}
            </div>
          )
        })}

        <p className="text-center text-xs text-slate-600 pb-4 flex items-center justify-center gap-1">
          <ExclamationTriangleIcon className="h-3.5 w-3.5" />
          Net worth and bank balances are estimates from your uploaded statements, not live bank feeds.
        </p>
      </div>
    </DashboardLayout>
  )
}
