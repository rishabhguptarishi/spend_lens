import { Link, router, usePage } from '@inertiajs/react'
import { useMemo, useState } from 'react'
import DashboardLayout from '../../Layouts/DashboardLayout'

const FILING_STEPS = [
  'Register or log in at incometax.gov.in',
  'Select the correct Assessment Year and ITR form (see suggestion below)',
  'Pre-fill income from Form 16 / bank credits and verify each schedule',
  'Report capital gains and foreign assets schedules if applicable',
  'Verify tax paid (Form 26AS) and TDS credits',
  'Choose old vs new tax regime on the portal',
  'Preview, submit, and e-verify your return',
]

const PRIORITY_BADGE = {
  high: 'bg-rose-500/20 text-rose-200 border-rose-500/30',
  medium: 'bg-amber-500/20 text-amber-200 border-amber-500/30',
  low: 'bg-emerald-500/20 text-emerald-200 border-emerald-500/30',
}

function formatInr(n) {
  return `₹${Number(n || 0).toLocaleString('en-IN')}`
}

// Single upload slot. Handles both singleton (Form 26AS, AIS) and
// multi-instance (Form 16A from many banks, LIC, rent receipts) types.
// For multi-instance, expanded mode shows all existing uploads as a
// list plus a fresh upload form with optional payer_name.
function DocumentSlot({ entry, year }) {
  const [uploading, setUploading] = useState(false)
  const [showMore, setShowMore] = useState(false)
  const [payerName, setPayerName] = useState('')
  const { ai_provider_label = 'AI' } = usePage().props
  const fileInputRef = useMemo(() => ({}), [])

  const handleFile = (e) => {
    const file = e.target.files?.[0]
    if (!file) return
    setUploading(true)
    const formData = new FormData()
    formData.append('file', file)
    formData.append('document_type', entry.key)
    formData.append('financial_year_start', year)
    if (entry.multiple_per_fy && payerName) formData.append('payer_name', payerName)
    router.post('/itr/documents', formData, {
      forceFormData: true,
      onFinish: () => {
        setUploading(false)
        setPayerName('')
        if (e.target) e.target.value = ''
      },
    })
  }

  const helperHint = entry.deduction_cap
    ? `Section ${entry.deduction_section} · cap ₹${entry.deduction_cap.toLocaleString('en-IN')}`
    : entry.deduction_section
      ? `Section ${entry.deduction_section} · no upper cap`
      : `Parses via ${ai_provider_label}`

  const renderInstance = (instance) => (
    <div
      key={instance.id}
      className="flex items-center justify-between px-3 py-2 rounded-lg bg-emerald-500/10 border border-emerald-500/30 text-xs"
    >
      <div className="flex items-center gap-2">
        <span className="text-emerald-300">✓</span>
        <span className="text-slate-200">{instance.label}</span>
        {instance.extraction_status && (
          <span className="text-slate-500">· {instance.extraction_status}</span>
        )}
      </div>
      <div className="flex gap-2">
        {instance.extracted && (
          <Link
            href={`/itr/documents/${instance.id}/confirm`}
            className="text-violet-300 hover:underline"
          >
            Review
          </Link>
        )}
        <button
          type="button"
          onClick={() => router.delete(`/itr/documents/${instance.id}`)}
          className="text-red-400 hover:underline"
        >
          Remove
        </button>
      </div>
    </div>
  )

  // Singleton, already uploaded
  if (!entry.multiple_per_fy && entry.instances?.length > 0) {
    const first = entry.instances[0]
    return (
      <div className="flex items-center justify-between p-4 rounded-xl border bg-emerald-500/15 border-emerald-500/30 gap-3 flex-wrap">
        <div>
          <p className="font-medium text-slate-100">{entry.label}</p>
          <p className="text-xs text-slate-400">{helperHint}</p>
          <p className="text-sm text-emerald-300 mt-1">
            {first.extraction_status === 'confirmed'
              ? 'Confirmed'
              : first.extraction_status === 'extracted'
                ? 'Extracted — review'
                : first.extraction_status === 'extracting'
                  ? 'Extracting…'
                  : 'Uploaded'}
          </p>
        </div>
        <div className="flex gap-3">
          {first.extracted && (
            <Link href={`/itr/documents/${first.id}/confirm`} className="text-sm text-violet-300 font-medium hover:underline">
              Review
            </Link>
          )}
          <button
            type="button"
            onClick={() => router.delete(`/itr/documents/${first.id}`)}
            className="text-sm text-red-400 hover:underline"
          >
            Remove
          </button>
        </div>
      </div>
    )
  }

  // Multi-instance with existing uploads → show list + "Add another"
  if (entry.multiple_per_fy && entry.instances?.length > 0) {
    return (
      <div className="p-4 rounded-xl border border-emerald-500/30 bg-emerald-500/5 space-y-2">
        <div className="flex items-start justify-between gap-3 flex-wrap">
          <div>
            <p className="font-medium text-slate-100">
              {entry.label}{' '}
              <span className="text-xs text-emerald-300 ml-1">({entry.instances.length} uploaded)</span>
            </p>
            <p className="text-xs text-slate-400">{helperHint}</p>
          </div>
          <button
            type="button"
            onClick={() => setShowMore((v) => !v)}
            className="text-xs text-violet-300 hover:underline"
          >
            {showMore ? 'Hide' : 'Add another'}
          </button>
        </div>

        <div className="space-y-1">{entry.instances.map(renderInstance)}</div>

        {showMore && (
          <label className="flex items-center justify-between gap-3 p-3 rounded-lg border border-dashed border-white/10 hover:border-violet-500/40 cursor-pointer flex-wrap">
            <input
              type="text"
              value={payerName}
              onChange={(e) => setPayerName(e.target.value)}
              placeholder="Payer / source label (e.g. HDFC Bank)"
              className="flex-1 min-w-[180px] px-3 py-1.5 text-sm rounded-lg bg-slate-900/40 border border-white/10 text-slate-200"
              onClick={(e) => e.stopPropagation()}
            />
            <span className="text-sm text-violet-400 font-medium">{uploading ? 'Uploading…' : 'Upload file'}</span>
            <input
              type="file"
              accept={entry.accept}
              className="hidden"
              onChange={handleFile}
              disabled={uploading}
            />
          </label>
        )}
      </div>
    )
  }

  // Empty state — first upload of this type
  return (
    <label className="flex items-center justify-between p-4 rounded-xl border border-dashed border-white/10 hover:border-violet-500/40 cursor-pointer gap-3 flex-wrap">
      <div className="flex-1">
        <p className="font-medium text-slate-100">{entry.label}</p>
        <p className="text-xs text-slate-400">{entry.description}</p>
        <p className="text-xs text-slate-500 mt-0.5">{helperHint}</p>
      </div>
      {entry.multiple_per_fy && (
        <input
          type="text"
          value={payerName}
          onChange={(e) => setPayerName(e.target.value)}
          placeholder="Payer (optional)"
          className="px-3 py-1.5 text-sm rounded-lg bg-slate-900/40 border border-white/10 text-slate-200"
          onClick={(e) => e.stopPropagation()}
        />
      )}
      <span className="text-sm text-violet-400 font-medium">{uploading ? 'Uploading…' : 'Upload'}</span>
      <input
        type="file"
        accept={entry.accept || '.pdf,.json'}
        className="hidden"
        onChange={handleFile}
        disabled={uploading}
      />
    </label>
  )
}

function SavingsAdvisor({ savings }) {
  if (!savings) return null

  const recs = savings.recommendations || []
  if (recs.length === 0) {
    return (
      <div className="sl-card rounded-2xl p-6 border border-white/10">
        <h2 className="text-lg font-semibold text-slate-100 mb-1">Tax savings advisor</h2>
        <p className="text-sm text-slate-400">No specific recommendations yet — upload Form 16, AIS, and a few deduction proofs to unlock advice.</p>
      </div>
    )
  }

  return (
    <div className="sl-card rounded-2xl p-6 border border-white/10">
      <div className="flex items-start justify-between gap-3 mb-4 flex-wrap">
        <div>
          <h2 className="text-lg font-semibold text-slate-100">Tax savings advisor</h2>
          <p className="text-sm text-slate-400">
            Estimated <span className="text-emerald-300 font-semibold">{formatInr(savings.total_potential_saving)}</span>{' '}
            in additional tax savings available · marginal rate{' '}
            {Math.round((savings.marginal_rate_used || 0) * 100)}%
          </p>
        </div>
        {savings.regime_recommendation && (
          <div className="text-xs text-slate-300 px-3 py-1.5 rounded-full bg-violet-500/15 border border-violet-500/30">
            Regime suggestion: <strong className="uppercase">{savings.regime_recommendation}</strong>
            {savings.regime_savings > 0 && (
              <span className="text-slate-400 ml-1">(saves {formatInr(savings.regime_savings)})</span>
            )}
          </div>
        )}
      </div>

      <ul className="space-y-3">
        {recs.map((rec) => (
          <li
            key={rec.section}
            className="p-4 rounded-xl border border-white/10 bg-slate-900/30 flex flex-col gap-2"
          >
            <div className="flex items-start justify-between gap-3 flex-wrap">
              <div className="flex items-center gap-2 flex-wrap">
                <span className={`text-xs px-2 py-0.5 rounded-full border ${PRIORITY_BADGE[rec.priority] || PRIORITY_BADGE.low}`}>
                  {rec.priority?.toUpperCase()}
                </span>
                <span className="font-semibold text-slate-100">{rec.label}</span>
              </div>
              {rec.potential_saving > 0 && (
                <span className="text-sm font-semibold text-emerald-300">
                  Save ~{formatInr(rec.potential_saving)}
                </span>
              )}
            </div>

            <p className="text-sm text-slate-300">{rec.action}</p>

            {(rec.cap || rec.used > 0) && (
              <div className="text-xs text-slate-500 flex items-center gap-3 flex-wrap">
                {rec.cap && <span>Cap: {formatInr(rec.cap)}</span>}
                {rec.used > 0 && <span>Used: {formatInr(rec.used)}</span>}
                {rec.remaining != null && <span>Remaining: {formatInr(rec.remaining)}</span>}
              </div>
            )}

            {rec.cap && rec.used > 0 && (
              <div className="h-1.5 rounded-full bg-slate-800 overflow-hidden">
                <div
                  className="h-full bg-violet-500"
                  style={{ width: `${Math.min(100, (rec.used / rec.cap) * 100)}%` }}
                />
              </div>
            )}
          </li>
        ))}
      </ul>

      <p className="text-xs text-slate-500 mt-4">{savings.disclaimer}</p>
    </div>
  )
}

export default function ItrIndex({
  year,
  years = [],
  financial_year_label: fyLabel,
  income = 0,
  expenses = 0,
  by_category = {},
  by_month = {},
  readiness = null,
  tax_savings = null,
  document_catalog = [],
}) {
  const net = income - expenses
  const categoryEntries = Object.entries(by_category).sort((a, b) => b[1] - a[1])
  const monthEntries = Object.entries(by_month).sort((a, b) => new Date(a[0]) - new Date(b[0]))
  const inv = readiness?.investment_summary || {}
  const checklist = readiness?.checklist || []
  const readinessPct = readiness?.readiness_pct ?? 0
  const dataSource = readiness?.data_source || 'generated'

  return (
    <DashboardLayout title="ITR Assistant">
      <div className="max-w-5xl mx-auto">
        <div className="flex justify-between items-center mb-6 flex-wrap gap-4">
          <div className="flex items-center gap-4 flex-wrap">
            <h1 className="text-2xl font-bold text-slate-100">ITR Assistant</h1>
            {years.length > 0 && (
              <select
                value={year}
                onChange={(e) => router.get('/itr', { year: e.target.value })}
                className="px-3 py-2 rounded-lg border border-white/10 focus:ring-2 focus:ring-violet-500"
              >
                {years.map((y) => (
                  <option key={y} value={y}>
                    FY {y}-{String((y + 1) % 100).padStart(2, '0')}
                  </option>
                ))}
              </select>
            )}
          </div>
          <div className="flex gap-2 flex-wrap">
            <a href={`/itr/tax_pack?year=${year}`} className="px-4 py-2 bg-emerald-600 text-white font-medium rounded-lg hover:bg-emerald-700">
              Tax pack ZIP
            </a>
            <a href={`/itr/export?year=${year}&format=csv`} className="px-4 py-2 bg-slate-700 text-white font-medium rounded-lg hover:bg-slate-800">
              CSV
            </a>
            <a href={`/itr/export?year=${year}&format=xlsx`} className="sl-btn-primary">
              Excel
            </a>
          </div>
        </div>

        <div className="flex flex-wrap gap-2 mb-6">
          <Link href={`/itr/reconciliation?year=${year}`} className="px-3 py-1.5 rounded-lg sl-card border text-sm font-medium text-slate-300 hover:bg-white/5">
            AIS reconciliation
          </Link>
          <Link href={`/itr/regime?year=${year}`} className="px-3 py-1.5 rounded-lg sl-card border text-sm font-medium text-slate-300 hover:bg-white/5">
            Regime compare
          </Link>
          <Link href={`/itr/capital_gains?year=${year}`} className="px-3 py-1.5 rounded-lg sl-card border text-sm font-medium text-slate-300 hover:bg-white/5">
            Capital gains
          </Link>
          <Link href={`/ai?mode=itr&year=${year}`} className="px-3 py-1.5 rounded-lg sl-card border text-sm font-medium text-violet-300 hover:bg-violet-500/10">
            Ask Savvy (ITR)
          </Link>
        </div>

        <div className="mb-6 sl-alert-warning text-sm">
          <strong className="font-semibold text-amber-200">Disclaimer:</strong> SpendLens provides assistive summaries and checklists only. This is not tax advice and not a substitute for a Chartered Accountant. You file on{' '}
          <a href="https://www.incometax.gov.in" target="_blank" rel="noopener noreferrer" className="underline decoration-amber-300/50 hover:decoration-amber-200">
            incometax.gov.in
          </a>
          .
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
          <div className="md:col-span-1 sl-card rounded-2xl p-6 shadow-sm border border-white/10">
            <p className="text-sm font-medium text-slate-500 uppercase">Filing readiness</p>
            <p className="text-4xl font-bold text-violet-400 mt-2">{readinessPct}%</p>
            <p className="text-xs text-slate-500 mt-2">
              {dataSource === 'generated' ? 'Generated from your bank data' : 'Mixed: uploads + bank data'}
            </p>
            {readiness?.suggested_itr_form && (
              <div className="mt-4 pt-4 border-t border-white/10">
                <p className="text-xs text-slate-500 uppercase">Suggested form</p>
                <p className="font-semibold text-slate-100">{readiness.suggested_itr_form.form}</p>
                <p className="text-xs text-slate-400 mt-1">{readiness.suggested_itr_form.reason}</p>
              </div>
            )}
          </div>
          <div className="md:col-span-2 sl-card rounded-2xl p-6 shadow-sm border border-white/10">
            <h2 className="text-sm font-semibold text-slate-100 mb-3">Readiness checklist — FY {fyLabel}</h2>
            <ul className="space-y-2 max-h-[420px] overflow-y-auto pr-2">
              {checklist.map((item) => (
                <li key={item.id} className="flex items-start gap-2 text-sm">
                  <span className={item.done ? 'text-green-600' : 'text-slate-300'}>{item.done ? '✓' : '○'}</span>
                  <span className={item.done ? 'text-slate-300' : 'text-slate-400'}>
                    {item.label}
                    {item.optional && <span className="text-slate-400 ml-1">(recommended)</span>}
                    {item.hint && (
                      <span className="block text-xs text-slate-400">{item.hint}</span>
                    )}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        </div>

        {tax_savings && (
          <div className="mb-8">
            <SavingsAdvisor savings={tax_savings} />
          </div>
        )}

        <div className="mb-8 space-y-6">
          <div>
            <h2 className="text-lg font-semibold text-slate-100 mb-1">Tax documents</h2>
            <p className="text-sm text-slate-400 mb-3">
              Aligned with ClearTax / Quicko / TaxBuddy. Categories filtered for {readiness?.suggested_itr_form?.form || 'ITR-1'}.
            </p>
          </div>

          {document_catalog.map((category) => (
            <div key={category.key} className="sl-card rounded-2xl p-5 border border-white/10">
              <div className="mb-3">
                <h3 className="text-base font-semibold text-slate-100">{category.label}</h3>
                <p className="text-xs text-slate-500">{category.description}</p>
              </div>
              <div className="space-y-2">
                {category.entries.map((entry) => (
                  <DocumentSlot key={entry.key} entry={entry} year={year} />
                ))}
              </div>
            </div>
          ))}

          <Link href="/investments/import" className="inline-block text-sm text-violet-400 hover:underline">
            Import full tradebook from Investments →
          </Link>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <div className="sl-card rounded-2xl p-6 shadow-sm border border-white/10">
            <p className="text-sm font-medium text-slate-500 uppercase">Total income (bank)</p>
            <p className="text-2xl font-bold text-violet-400 mt-1">{formatInr(income)}</p>
            {readiness?.salary_estimate > 0 && (
              <p className="text-xs text-slate-500 mt-1">Salary-like credits: {formatInr(readiness.salary_estimate)}</p>
            )}
          </div>
          <div className="sl-card rounded-2xl p-6 shadow-sm border border-white/10">
            <p className="text-sm font-medium text-slate-500 uppercase">Expenses (bank)</p>
            <p className="text-2xl font-bold text-red-600 mt-1">{formatInr(expenses)}</p>
          </div>
          <div className="sl-card rounded-2xl p-6 shadow-sm border border-white/10">
            <p className="text-sm font-medium text-slate-500 uppercase">Net</p>
            <p className={`text-2xl font-bold mt-1 ${net >= 0 ? 'text-violet-400' : 'text-red-600'}`}>{formatInr(net)}</p>
          </div>
        </div>

        {(inv.transaction_count > 0 || inv.holdings_count > 0) && (
          <div className="mb-8 sl-card rounded-2xl p-6 shadow-sm border border-white/10">
            <h2 className="text-lg font-semibold text-slate-100 mb-3">Investment summary (FY)</h2>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm">
              <div>
                <p className="text-slate-500">Contributions</p>
                <p className="font-semibold">{formatInr(inv.contributions)}</p>
              </div>
              <div>
                <p className="text-slate-500">Sells / maturity</p>
                <p className="font-semibold">{formatInr(inv.sells)}</p>
              </div>
              <div>
                <p className="text-slate-500">Dividends & interest</p>
                <p className="font-semibold">{formatInr(inv.dividends_interest)}</p>
              </div>
              <div>
                <p className="text-slate-500">Holdings</p>
                <p className="font-semibold">{inv.holdings_count}</p>
              </div>
            </div>
          </div>
        )}

        <div className="mb-8">
          <h2 className="text-lg font-semibold text-slate-100 mb-3">Filing guide (incometax.gov.in)</h2>
          <ol className="list-decimal list-inside space-y-2 sl-card rounded-2xl p-6 border border-white/10 text-slate-300 text-sm">
            {FILING_STEPS.map((step, i) => (
              <li key={i}>{step}</li>
            ))}
          </ol>
        </div>

        {categoryEntries.length > 0 && (
          <div className="mb-8">
            <h2 className="text-lg font-semibold text-slate-100 mb-4">Expenses by category</h2>
            <div className="sl-card rounded-2xl shadow-sm border border-white/10 overflow-hidden">
              <table className="min-w-full">
                <thead className="bg-white/5">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">Category</th>
                    <th className="px-6 py-3 text-right text-xs font-medium text-slate-500 uppercase">Amount</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-200">
                  {categoryEntries.map(([name, amount]) => (
                    <tr key={name}>
                      <td className="px-6 py-4 text-slate-100">{name}</td>
                      <td className="px-6 py-4 text-right font-medium text-red-600">{formatInr(amount)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {monthEntries.length > 0 && (
          <div>
            <h2 className="text-lg font-semibold text-slate-100 mb-4">Monthly expenses</h2>
            <div className="sl-card rounded-2xl shadow-sm border border-white/10 overflow-hidden">
              <table className="min-w-full">
                <thead className="bg-white/5">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">Month</th>
                    <th className="px-6 py-3 text-right text-xs font-medium text-slate-500 uppercase">Amount</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-200">
                  {monthEntries.map(([month, amount]) => (
                    <tr key={month}>
                      <td className="px-6 py-4 text-slate-100">{month}</td>
                      <td className="px-6 py-4 text-right font-medium text-red-600">{formatInr(amount)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {categoryEntries.length === 0 && monthEntries.length === 0 && (
          <div className="sl-card rounded-2xl p-12 text-center border border-white/10">
            <p className="text-slate-400">No transactions for this financial year. Upload statements to build your default ITR summary.</p>
          </div>
        )}
      </div>
    </DashboardLayout>
  )
}
