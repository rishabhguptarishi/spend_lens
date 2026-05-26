import { Link, router } from '@inertiajs/react'
import { useMemo, useState } from 'react'
import DashboardLayout from '../../../Layouts/DashboardLayout'

const fmtAmount = (v) => `₹${Number(v).toLocaleString('en-IN', { maximumFractionDigits: 2 })}`

export default function InvestmentImportPreview({ batch }) {
  const [rows, setRows] = useState(batch.preview_rows || [])

  const toggle = (idx) => {
    const next = [...rows]
    next[idx] = { ...next[idx], selected: !next[idx].selected }
    setRows(next)
  }

  const confirm = () => {
    router.post(`/investments/import/${batch.id}/confirm`, { rows })
  }

  const hasAccountHints = useMemo(() => rows.some((r) => r.account_hint), [rows])
  const accountBreakdown = useMemo(() => {
    if (!hasAccountHints) return []
    const map = new Map()
    rows
      .filter((r) => r.selected !== false)
      .forEach((r) => {
        const k = r.account_hint || '—'
        const cur = map.get(k) || { count: 0, total: 0 }
        cur.count += 1
        cur.total += Number(r.amount) || 0
        map.set(k, cur)
      })
    return Array.from(map.entries()).sort((a, b) => b[1].total - a[1].total)
  }, [rows, hasAccountHints])

  return (
    <DashboardLayout title="Import preview">
      <div className="max-w-5xl mx-auto">
        <Link href="/investments/import" className="text-sm text-violet-400 hover:underline mb-4 inline-block">
          ← Import
        </Link>
        <h1 className="text-2xl font-bold text-slate-100 mb-1">Preview — {batch.filename}</h1>
        <p className="text-slate-400 text-sm mb-6">
          {batch.source} · FY {batch.financial_year_label} · {rows.length} rows in preview
          {batch.truncated && batch.row_count > rows.length && (
            <span className="block text-amber-700 mt-1">
              Showing first {rows.length} of {batch.row_count} parsed rows. Import applies to preview only.
            </span>
          )}
        </p>

        {hasAccountHints && (
          <div className="sl-card border border-white/10 rounded-xl p-4 mb-4">
            <h2 className="text-sm font-medium text-slate-300 mb-2">
              Will create / use these accounts ({accountBreakdown.length})
            </h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
              {accountBreakdown.map(([name, { count, total }]) => (
                <div
                  key={name}
                  className="flex items-baseline justify-between px-3 py-2 rounded-lg bg-white/5 border border-white/5"
                >
                  <span className="text-slate-100 font-medium truncate" title={name}>
                    {name}
                  </span>
                  <span className="text-xs text-slate-400 whitespace-nowrap ml-2">
                    {count} · {fmtAmount(total)}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        <div className="mb-4 flex gap-2">
          <button
            type="button"
            onClick={confirm}
            className="sl-btn-primary text-white font-medium rounded-lg"
          >
            Import selected
          </button>
          <button
            type="button"
            onClick={() => router.delete(`/investments/import/${batch.id}`)}
            className="px-4 py-2 border border-white/10 rounded-lg text-slate-300"
          >
            Cancel
          </button>
        </div>

        <div className="sl-card border overflow-hidden">
          <table className="min-w-full text-sm">
            <thead className="bg-white/5">
              <tr>
                <th className="px-3 py-2 text-left">✓</th>
                <th className="px-3 py-2 text-left">Date</th>
                <th className="px-3 py-2 text-left">Kind</th>
                {hasAccountHints && <th className="px-3 py-2 text-left">Account</th>}
                <th className="px-3 py-2 text-left">Description</th>
                {hasAccountHints && <th className="px-3 py-2 text-right">Units</th>}
                <th className="px-3 py-2 text-right">Amount</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {rows.map((r, i) => (
                <tr key={i} className={r.selected === false ? 'opacity-40' : ''}>
                  <td className="px-3 py-2">
                    <input type="checkbox" checked={r.selected !== false} onChange={() => toggle(i)} />
                  </td>
                  <td className="px-3 py-2 whitespace-nowrap">{r.date}</td>
                  <td className="px-3 py-2">{r.kind}</td>
                  {hasAccountHints && (
                    <td className="px-3 py-2 text-xs text-slate-300 whitespace-nowrap">{r.account_hint || '—'}</td>
                  )}
                  <td className="px-3 py-2 max-w-xs truncate" title={r.description}>
                    {r.description}
                  </td>
                  {hasAccountHints && (
                    <td className="px-3 py-2 text-right text-slate-400 tabular-nums">
                      {r.units != null && r.units !== '' ? Number(r.units).toLocaleString('en-IN', { maximumFractionDigits: 3 }) : '—'}
                    </td>
                  )}
                  <td className="px-3 py-2 text-right tabular-nums">{fmtAmount(r.amount)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </DashboardLayout>
  )
}
