import { useState, useMemo } from 'react'
import { Link } from '@inertiajs/react'
import {
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  Sector,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  Legend,
  AreaChart,
  Area,
  CartesianGrid,
  LineChart,
  Line,
} from 'recharts'
import {
  ArrowTrendingUpIcon,
  ArrowTrendingDownIcon,
  BanknotesIcon,
  DocumentArrowUpIcon,
  ChartPieIcon,
  WalletIcon,
  BriefcaseIcon,
  TagIcon,
  ArrowPathIcon,
  CreditCardIcon,
  SparklesIcon,
  DocumentTextIcon,
} from '@heroicons/react/24/outline'
import { chartAxisTick, chartLegendStyle, chartTooltipStyle } from '../../lib/chartTheme'

const QUICK_ACTIONS_LIST = [
  { href: '/upload', label: 'Upload', icon: DocumentArrowUpIcon, primary: true },
  { href: '/transactions', label: 'Transactions', icon: BanknotesIcon },
  { href: '/insights', label: 'Insights', icon: ChartPieIcon },
  { href: '/ai', label: 'Ask Savvy', icon: SparklesIcon },
  { href: '/itr', label: 'ITR', icon: DocumentTextIcon },
  { href: '/budgets', label: 'Budgets', icon: WalletIcon },
  { href: '/investments', label: 'Investments', icon: BriefcaseIcon },
]

export function formatCurrency(v) {
  return `₹${Number(v || 0).toLocaleString('en-IN', { maximumFractionDigits: 0 })}`
}

export function ChangeBadge({ pct, invert = false }) {
  if (pct == null) return null
  const up = pct > 0
  const favorable = invert ? !up : up
  return (
    <span
      className={`inline-flex items-center text-xs font-medium px-2 py-0.5 rounded-full ${
        favorable ? 'bg-emerald-500/20 text-emerald-300' : 'bg-red-500/20 text-red-300'
      }`}
    >
      {up ? '+' : ''}
      {pct}%
    </span>
  )
}

export function KpiCard({ title, value, sub, changePct, invertChange, icon: Icon, iconClass, href }) {
  const inner = (
    <div className="sl-card-hover p-5 h-full">
      <div className="flex items-start justify-between gap-2">
        <div className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-xl ${iconClass}`}>
          <Icon className="h-5 w-5" />
        </div>
        {changePct != null && <ChangeBadge pct={changePct} invert={invertChange} />}
      </div>
      <p className="mt-4 text-xs font-medium uppercase tracking-wide text-slate-500">{title}</p>
      <p className="mt-1 text-2xl font-bold text-white tabular-nums">{value}</p>
      {sub && <p className="mt-1 text-xs text-slate-400">{sub}</p>}
    </div>
  )
  return href ? (
    <Link href={href} className="block h-full">
      {inner}
    </Link>
  ) : (
    inner
  )
}

export function WidgetQuickActions() {
  return (
    <div className="flex gap-2 overflow-x-auto pb-1">
      {QUICK_ACTIONS_LIST.map(({ href, label, icon: Icon, primary }) => (
        <Link
          key={href}
          href={href}
          className={`inline-flex shrink-0 items-center gap-2 rounded-xl px-4 py-2.5 text-sm font-medium transition ${
            primary
              ? 'bg-gradient-to-r from-violet-600 to-fuchsia-600 text-white shadow-lg shadow-violet-600/20'
              : 'border border-white/10 bg-white/5 text-slate-200 hover:bg-white/10'
          }`}
        >
          <Icon className="h-4 w-4" />
          {label}
        </Link>
      ))}
    </div>
  )
}

export function WidgetAlerts({ ctx }) {
  const { pending_investment_suggestions, uncategorized_count, overBudgets, recurring_count } = ctx
  if (
    pending_investment_suggestions <= 0 &&
    uncategorized_count <= 0 &&
    overBudgets.length <= 0 &&
    recurring_count <= 0
  ) {
    return null
  }
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
      {pending_investment_suggestions > 0 && (
        <Link href="/investments/suggestions" className="sl-alert-warning text-sm hover:border-amber-400/50 transition">
          <strong>{pending_investment_suggestions}</strong> investment suggestion
          {pending_investment_suggestions !== 1 ? 's' : ''} to review
        </Link>
      )}
      {uncategorized_count > 0 && (
        <Link href="/transactions" className="sl-alert-info text-sm flex items-center gap-2">
          <TagIcon className="h-4 w-4 shrink-0" />
          {uncategorized_count} uncategorized expense
          {uncategorized_count !== 1 ? 's' : ''}
        </Link>
      )}
      {overBudgets.length > 0 && (
        <Link href="/budgets" className="sl-alert-error text-sm">
          {overBudgets.length} budget{overBudgets.length !== 1 ? 's' : ''} over limit
        </Link>
      )}
      {recurring_count > 0 && (
        <div className="sl-card p-3 text-sm text-slate-300 flex items-center gap-2">
          <ArrowPathIcon className="h-4 w-4 text-violet-400" />
          {recurring_count} recurring payment{recurring_count !== 1 ? 's' : ''} this period
        </div>
      )}
    </div>
  )
}

export function WidgetHero({ ctx }) {
  const { net_flow, income, expenses, savings_rate, transaction_count } = ctx
  return (
    <div className="relative overflow-hidden rounded-2xl border border-violet-500/30 bg-gradient-to-br from-violet-600/25 via-slate-900 to-fuchsia-600/15 p-6 sm:p-8">
      <div className="absolute top-0 right-0 w-64 h-64 bg-fuchsia-500/10 rounded-full blur-3xl pointer-events-none" />
      <div className="relative flex flex-col sm:flex-row sm:items-end sm:justify-between gap-6">
        <div>
          <p className="text-sm font-medium text-violet-200/90 uppercase tracking-wider">Net cash flow</p>
          <p className={`mt-2 text-4xl sm:text-5xl font-bold tabular-nums ${net_flow >= 0 ? 'text-white' : 'text-red-300'}`}>
            {net_flow >= 0 ? '+' : ''}
            {formatCurrency(net_flow)}
          </p>
          <p className="mt-2 text-slate-400 text-sm">
            Income {formatCurrency(income)} − Expenses {formatCurrency(expenses)}
          </p>
        </div>
        <div className="flex flex-wrap gap-6 sm:text-right">
          {savings_rate != null && (
            <div>
              <p className="text-xs text-slate-500 uppercase">Savings rate</p>
              <p className={`text-2xl font-bold ${savings_rate >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
                {savings_rate}%
              </p>
            </div>
          )}
          <div>
            <p className="text-xs text-slate-500 uppercase">Transactions</p>
            <p className="text-2xl font-bold text-white">{transaction_count}</p>
          </div>
        </div>
      </div>
    </div>
  )
}

export function WidgetKpis({ ctx }) {
  const { income, expenses, net_flow, income_change_pct, expenses_change_pct, net_worth, savings_rate } = ctx
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
      <KpiCard
        title="Income"
        value={formatCurrency(income)}
        changePct={income_change_pct}
        icon={ArrowTrendingUpIcon}
        iconClass="bg-emerald-500/20 text-emerald-400"
        href="/transactions"
      />
      <KpiCard
        title="Expenses"
        value={formatCurrency(expenses)}
        changePct={expenses_change_pct}
        invertChange
        icon={ArrowTrendingDownIcon}
        iconClass="bg-red-500/20 text-red-400"
        href="/transactions"
      />
      <KpiCard
        title="Net flow"
        value={formatCurrency(net_flow)}
        sub={net_flow >= 0 ? 'Surplus' : 'Deficit'}
        icon={WalletIcon}
        iconClass="bg-violet-500/20 text-violet-400"
        href="/insights"
      />
      <KpiCard
        title="Net worth (approx)"
        value={formatCurrency(net_worth.net_worth_approx)}
        sub={`Bank ${formatCurrency(net_worth.total_bank)} · Invested ${formatCurrency(net_worth.total_invested)}`}
        icon={BriefcaseIcon}
        iconClass="bg-fuchsia-500/20 text-fuchsia-400"
        href="/net_worth"
      />
    </div>
  )
}

export function WidgetDailySparkline({ dailySpend }) {
  const points = dailySpend?.points || []
  if (points.length === 0) return null

  return (
    <div className="sl-card p-6">
      <div className="flex flex-wrap items-start justify-between gap-4 mb-4">
        <div>
          <h3 className="sl-section-title">Daily spending</h3>
          <p className="text-xs text-slate-500 mt-1">Last {dailySpend.days} days of expenses</p>
        </div>
        <div className="flex gap-6 text-sm">
          <div>
            <p className="text-slate-500 text-xs uppercase">Total</p>
            <p className="font-semibold text-white tabular-nums">{formatCurrency(dailySpend.total)}</p>
          </div>
          <div>
            <p className="text-slate-500 text-xs uppercase">Daily avg</p>
            <p className="font-semibold text-violet-300 tabular-nums">{formatCurrency(dailySpend.daily_average)}</p>
          </div>
        </div>
      </div>
      <div className="h-40">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={points}>
            <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
            <XAxis dataKey="date" tick={chartAxisTick} interval="preserveStartEnd" />
            <YAxis tickFormatter={(v) => `₹${(v / 1000).toFixed(0)}k`} tick={chartAxisTick} width={48} />
            <Tooltip contentStyle={chartTooltipStyle.contentStyle} formatter={(v) => formatCurrency(v)} />
            <Line type="monotone" dataKey="amount" name="Spent" stroke="#a78bfa" strokeWidth={2} dot={false} />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  )
}

export function WidgetBudgetVsActual({ budgetVsActual, period_label }) {
  if (!budgetVsActual?.length) return null

  return (
    <div className="sl-card p-6">
      <h3 className="sl-section-title mb-1">Budget vs actual</h3>
      <p className="text-xs text-slate-500 mb-4">{period_label} — categories with budgets set</p>
      <div className="h-72">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={budgetVsActual} layout="vertical" margin={{ left: 8, right: 16 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" horizontal={false} />
            <XAxis type="number" tickFormatter={(v) => `₹${(v / 1000).toFixed(0)}k`} tick={chartAxisTick} />
            <YAxis type="category" dataKey="name" tick={chartAxisTick} width={100} />
            <Tooltip contentStyle={chartTooltipStyle.contentStyle} formatter={(v) => formatCurrency(v)} />
            <Legend wrapperStyle={chartLegendStyle} />
            <Bar dataKey="budget" name="Budget" fill="#8b5cf6" radius={[0, 4, 4, 0]} barSize={12} />
            <Bar dataKey="actual" name="Actual" fill="#f472b6" radius={[0, 4, 4, 0]} barSize={12} />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  )
}

// Active-slice renderer: the hovered wedge expands outward, gains a thin
// stroke, and a faint outer ring is drawn so the focal segment reads
// clearly against the others (which dim in the parent component).
function ActivePieSlice(props) {
  const { cx, cy, innerRadius, outerRadius, startAngle, endAngle, fill } = props
  return (
    <g>
      <Sector
        cx={cx}
        cy={cy}
        innerRadius={innerRadius}
        outerRadius={outerRadius + 6}
        startAngle={startAngle}
        endAngle={endAngle}
        fill={fill}
        stroke="#0f172a"
        strokeWidth={2}
      />
      <Sector
        cx={cx}
        cy={cy}
        innerRadius={outerRadius + 8}
        outerRadius={outerRadius + 10}
        startAngle={startAngle}
        endAngle={endAngle}
        fill={fill}
        opacity={0.35}
      />
    </g>
  )
}

function SpendingPieTooltip({ active, payload, total }) {
  if (!active || !payload?.length) return null
  const { name, value, payload: row } = payload[0]
  const color = row?.color || '#64748b'
  const pct = total > 0 ? (Number(value) / total) * 100 : 0
  return (
    <div className="rounded-xl bg-slate-900/95 border border-white/20 px-3 py-2 shadow-xl shadow-black/40 backdrop-blur-sm">
      <div className="flex items-center gap-2 mb-0.5">
        <span className="inline-block h-2.5 w-2.5 rounded-sm" style={{ backgroundColor: color }} />
        <span className="text-slate-100 font-medium text-sm">{name}</span>
      </div>
      <div className="text-slate-100 text-base font-semibold leading-tight">{formatCurrency(value)}</div>
      <div className="text-slate-400 text-xs mt-0.5">{pct.toFixed(1)}% of total</div>
    </div>
  )
}

function SpendingPie({ data }) {
  const [activeIndex, setActiveIndex] = useState(null)
  const total = useMemo(
    () => data.reduce((sum, d) => sum + Number(d.value || 0), 0),
    [data],
  )

  return (
    <ResponsiveContainer width="100%" height="100%">
      <PieChart>
        <Pie
          data={data}
          dataKey="value"
          nameKey="name"
          cx="50%"
          cy="50%"
          innerRadius={48}
          outerRadius={78}
          paddingAngle={1}
          stroke="rgba(15,23,42,0.6)"
          strokeWidth={1}
          activeIndex={activeIndex ?? -1}
          activeShape={ActivePieSlice}
          onMouseEnter={(_, i) => setActiveIndex(i)}
          onMouseLeave={() => setActiveIndex(null)}
          isAnimationActive={false}
        >
          {data.map((entry, i) => (
            <Cell
              key={i}
              fill={entry.color || '#64748b'}
              opacity={activeIndex == null || activeIndex === i ? 1 : 0.35}
              style={{ transition: 'opacity 150ms ease, transform 150ms ease', cursor: 'pointer' }}
            />
          ))}
        </Pie>
        <Tooltip
          content={<SpendingPieTooltip total={total} />}
          // allowEscapeViewBox lets the tooltip render outside the
          // ResponsiveContainer bounds — important when hovering edge
          // slices in a narrow card so the popup doesn't get clipped.
          allowEscapeViewBox={{ x: true, y: true }}
          wrapperStyle={{ outline: 'none', zIndex: 30, pointerEvents: 'none' }}
          cursor={false}
        />
      </PieChart>
    </ResponsiveContainer>
  )
}

export function WidgetCharts({ ctx }) {
  const { spending_by_category, monthly_trend, period_label } = ctx
  if (spending_by_category.length === 0 && monthly_trend.length === 0) return null

  return (
    <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
      {spending_by_category.length > 0 && (
        <div className="sl-card p-6 xl:col-span-1">
          <h3 className="sl-section-title mb-1">Spending by category</h3>
          <p className="text-xs text-slate-500 mb-4">{period_label}</p>
          <div className="h-56">
            <SpendingPie data={spending_by_category} />
          </div>
        </div>
      )}
      {monthly_trend.length > 0 && (
        <div className="sl-card p-6 xl:col-span-2">
          <h3 className="sl-section-title mb-1">Cash flow trend</h3>
          <p className="text-xs text-slate-500 mb-4">Last 6 months</p>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={monthly_trend}>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
                <XAxis dataKey="month" tick={chartAxisTick} />
                <YAxis tickFormatter={(v) => `₹${(v / 1000).toFixed(0)}k`} tick={chartAxisTick} />
                <Tooltip contentStyle={chartTooltipStyle.contentStyle} formatter={(v) => formatCurrency(v)} />
                <Legend wrapperStyle={chartLegendStyle} />
                <Area type="monotone" dataKey="income" name="Income" stroke="#10b981" fill="#10b981" fillOpacity={0.12} />
                <Area type="monotone" dataKey="expenses" name="Expenses" stroke="#ef4444" fill="#ef4444" fillOpacity={0.12} />
                <Area type="monotone" dataKey="net" name="Net" stroke="#8b5cf6" fillOpacity={0.08} strokeWidth={2} />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>
      )}
    </div>
  )
}

export function WidgetTopSpend({ ctx }) {
  const { top_merchants, top_categories, maxCategoryAmount } = ctx
  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <div className="sl-card p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="sl-section-title">Top merchants</h3>
          <Link href="/insights" className="sl-btn-ghost text-xs">
            Insights →
          </Link>
        </div>
        {top_merchants.length === 0 ? (
          <p className="text-sm text-slate-500">No merchant data for this period.</p>
        ) : (
          <ul className="space-y-3">
            {top_merchants.map((m) => (
              <li key={m.merchant}>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-slate-200 truncate pr-2">{m.merchant}</span>
                  <span className="text-slate-400 tabular-nums shrink-0">{formatCurrency(m.amount)}</span>
                </div>
                <div className="h-1.5 bg-white/10 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-violet-500 rounded-full"
                    style={{ width: `${Math.min(100, (m.amount / top_merchants[0].amount) * 100)}%` }}
                  />
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
      <div className="sl-card p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="sl-section-title">Top categories</h3>
          <Link href="/transactions" className="sl-btn-ghost text-xs">
            View →
          </Link>
        </div>
        {top_categories.length === 0 ? (
          <p className="text-sm text-slate-500">No categorized spending yet.</p>
        ) : (
          <ul className="space-y-3">
            {top_categories.map((c) => (
              <li key={c.name}>
                <div className="flex justify-between text-sm mb-1">
                  <span className="flex items-center gap-2 text-slate-200">
                    <span className="w-2 h-2 rounded-full" style={{ backgroundColor: c.color }} />
                    {c.name}
                  </span>
                  <span className="text-slate-400 tabular-nums">{formatCurrency(c.amount)}</span>
                </div>
                <div className="h-1.5 bg-white/10 rounded-full overflow-hidden">
                  <div
                    className="h-full rounded-full"
                    style={{
                      width: `${Math.min(100, (c.amount / maxCategoryAmount) * 100)}%`,
                      backgroundColor: c.color || '#8b5cf6',
                    }}
                  />
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}

export function WidgetBudgetsItr({ ctx }) {
  const { budgets, itr, credit_cards_count } = ctx
  if (budgets.length === 0 && !itr && credit_cards_count <= 0) return null

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {budgets.length > 0 && (
        <div className="sl-card p-6 md:col-span-2">
          <div className="flex items-center justify-between mb-4">
            <h3 className="sl-section-title">Budgets</h3>
            <Link href="/budgets" className="sl-btn-ghost text-xs">
              Manage →
            </Link>
          </div>
          <ul className="space-y-4">
            {budgets.map((b) => (
              <li key={b.category_id}>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-slate-200">{b.category_name}</span>
                  <span className={b.remaining < 0 ? 'text-red-400' : 'text-slate-400'}>
                    {formatCurrency(b.spent)} / {formatCurrency(b.amount)}
                  </span>
                </div>
                <div className="h-2 bg-white/10 rounded-full overflow-hidden">
                  <div
                    className={`h-full rounded-full ${b.remaining < 0 ? 'bg-red-500' : b.pct_used > 80 ? 'bg-amber-500' : 'bg-violet-500'}`}
                    style={{ width: `${Math.min(100, b.pct_used || 0)}%` }}
                  />
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}
      {itr && (
        <Link href="/itr" className="block sl-card p-6 hover:border-violet-500/40 transition group h-full">
          <p className="text-xs text-slate-500 uppercase tracking-wide">ITR readiness</p>
          <p className="text-lg font-semibold text-white mt-1">{itr.financial_year_label}</p>
          <p className="text-sm text-slate-400 mt-1">Suggested: {itr.suggested_form || '—'}</p>
          <p className="text-4xl font-bold text-violet-400 mt-4">{itr.readiness_pct}%</p>
          <p className="text-xs text-violet-300 group-hover:underline mt-2">View checklist →</p>
        </Link>
      )}
      {credit_cards_count > 0 && (
        <Link href="/credit_cards/suggestions" className="flex items-center gap-3 sl-card p-4 hover:border-white/20 transition h-full">
          <CreditCardIcon className="h-8 w-8 text-amber-400 shrink-0" />
          <div>
            <p className="font-medium text-slate-100">Credit cards</p>
            <p className="text-xs text-slate-500">{credit_cards_count} card(s) · rewards</p>
          </div>
        </Link>
      )}
    </div>
  )
}

export function WidgetAccounts({ bank_accounts }) {
  if (!bank_accounts?.length) return null
  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h3 className="sl-section-title">Accounts</h3>
        <Link href="/bank_accounts" className="sl-btn-ghost text-sm">
          Manage →
        </Link>
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
        {bank_accounts.map((account) => (
          <Link key={account.id} href={`/bank_accounts/${account.id}`} className="sl-card-hover p-4">
            <div className="flex items-center gap-3">
              <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-violet-500/20">
                <BanknotesIcon className="h-5 w-5 text-violet-400" />
              </div>
              <div className="min-w-0">
                <p className="font-medium text-slate-100 truncate">{account.name}</p>
                <p className="text-xs text-slate-500 truncate">
                  {account.bank_name} · {account.statements?.length || 0} statements
                </p>
              </div>
            </div>
          </Link>
        ))}
      </div>
    </div>
  )
}

export function WidgetTransactions({ recent_transactions }) {
  if (!recent_transactions?.length) return null
  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h3 className="sl-section-title">Recent transactions</h3>
        <Link href="/transactions" className="sl-btn-ghost text-sm">
          View all →
        </Link>
      </div>
      <div className="sl-table-wrap">
        <table className="sl-table">
          <thead>
            <tr>
              <th>Date</th>
              <th>Description</th>
              <th>Category</th>
              <th className="text-right">Amount</th>
            </tr>
          </thead>
          <tbody>
            {recent_transactions.map((tx) => (
              <tr key={tx.id}>
                <td className="whitespace-nowrap text-slate-400">
                  {tx.date ? new Date(tx.date).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' }) : '—'}
                </td>
                <td className="font-medium text-slate-100 max-w-[200px] truncate">{tx.description || '—'}</td>
                <td>
                  <span className="sl-badge-slate">{tx.category?.name || 'Uncategorized'}</span>
                </td>
                <td
                  className={`text-right font-semibold tabular-nums ${
                    tx.transaction_type === 'credit' ? 'text-emerald-400' : 'text-red-400'
                  }`}
                >
                  {tx.transaction_type === 'credit' ? '+' : '−'}
                  {formatCurrency(Math.abs(parseFloat(tx.amount || 0)))}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

export const WIDGET_RENDERERS = {
  quick_actions: (ctx) => <WidgetQuickActions />,
  alerts: (ctx) => <WidgetAlerts ctx={ctx} />,
  hero: (ctx) => <WidgetHero ctx={ctx} />,
  kpis: (ctx) => <WidgetKpis ctx={ctx} />,
  daily_sparkline: (ctx) => <WidgetDailySparkline dailySpend={ctx.daily_spend} />,
  charts: (ctx) => <WidgetCharts ctx={ctx} />,
  budget_vs_actual: (ctx) => <WidgetBudgetVsActual budgetVsActual={ctx.budget_vs_actual} period_label={ctx.period_label} />,
  top_spend: (ctx) => <WidgetTopSpend ctx={ctx} />,
  budgets_itr: (ctx) => <WidgetBudgetsItr ctx={ctx} />,
  accounts: (ctx) => <WidgetAccounts bank_accounts={ctx.bank_accounts} />,
  transactions: (ctx) => <WidgetTransactions recent_transactions={ctx.recent_transactions} />,
}
