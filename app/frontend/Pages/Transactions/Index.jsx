import { Link, useForm, router } from '@inertiajs/react'
import { useRef, useState } from 'react'
import DashboardLayout from '../../Layouts/DashboardLayout'
import DateRangePresets from '../../Components/DateRangePresets'

export default function TransactionsIndex({ transactions = [], categories = [], bank_accounts = [], filters = {} }) {
  const [selected, setSelected] = useState(new Set())
  const [bulkCategory, setBulkCategory] = useState('')
  const { post: postBulk } = useForm()
  const formRef = useRef(null)

  // Preserve all current form values (search, category, account, type, recurring)
  // when a date preset is clicked — overlay just the date range and navigate.
  const applyPreset = ({ start_date, end_date }) => {
    const params = { from: start_date, to: end_date }
    if (formRef.current) {
      const fd = new FormData(formRef.current)
      for (const [k, v] of fd.entries()) {
        if (k === 'from' || k === 'to') continue
        if (v !== '' && v != null) params[k] = v
      }
    }
    router.get('/transactions', params)
  }

  const toggleSelect = (id) => {
    const next = new Set(selected)
    if (next.has(id)) next.delete(id)
    else next.add(id)
    setSelected(next)
  }

  const toggleAll = () => {
    if (selected.size === transactions.length) setSelected(new Set())
    else setSelected(new Set(transactions.map((t) => t.id)))
  }

  const handleBulkUpdate = () => {
    if (!bulkCategory || selected.size === 0) return
    postBulk('/transactions/bulk_update', {
      ids: [...selected],
      category_id: bulkCategory,
    })
    setSelected(new Set())
    setBulkCategory('')
  }

  return (
    <DashboardLayout title="Transactions">
      <div className="max-w-7xl mx-auto">
        {/* Filters */}
        <div className="sl-card p-4 mb-6 border border-white/10 space-y-3">
          <DateRangePresets
            onApply={applyPreset}
            currentStart={filters.from || ''}
            currentEnd={filters.to || ''}
          />
          <form ref={formRef} method="get" action="/transactions" className="flex flex-wrap gap-3 items-end">
            <div>
              <label className="block text-xs text-slate-500 mb-1">Search</label>
              <input
                type="text"
                name="q"
                defaultValue={filters.q}
                placeholder="Description..."
                className="px-3 py-2 rounded-lg border border-white/10 text-sm"
              />
            </div>
            <div>
              <label className="block text-xs text-slate-500 mb-1">Category</label>
              <select name="category_id" defaultValue={filters.category_id || ''} className="px-3 py-2 rounded-lg border border-white/10 text-sm">
                <option value="">All</option>
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>{c.name}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs text-slate-500 mb-1">Account</label>
              <select name="bank_account_id" defaultValue={filters.bank_account_id || ''} className="px-3 py-2 rounded-lg border border-white/10 text-sm">
                <option value="">All</option>
                {bank_accounts.map((a) => (
                  <option key={a.id} value={a.id}>{a.name}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs text-slate-500 mb-1">Type</label>
              <select name="type" defaultValue={filters.type || ''} className="px-3 py-2 rounded-lg border border-white/10 text-sm">
                <option value="">All</option>
                <option value="debit">Debit</option>
                <option value="credit">Credit</option>
              </select>
            </div>
            <div>
              <label className="block text-xs text-slate-500 mb-1">From</label>
              <input type="date" name="from" defaultValue={filters.from} className="px-3 py-2 rounded-lg border border-white/10 text-sm" />
            </div>
            <div>
              <label className="block text-xs text-slate-500 mb-1">To</label>
              <input type="date" name="to" defaultValue={filters.to} className="px-3 py-2 rounded-lg border border-white/10 text-sm" />
            </div>
            <label className="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" name="recurring" value="1" defaultChecked={filters.recurring === '1'} className="rounded" />
              <span className="text-sm text-slate-400">Recurring only</span>
            </label>
            <button type="submit" className="px-4 py-2 bg-slate-800 text-white rounded-lg text-sm font-medium">
              Filter
            </button>
          </form>
        </div>

        {/* Bulk actions */}
        {selected.size > 0 && (
          <div className="flex items-center gap-4 mb-4 p-4 bg-violet-500/10 rounded-xl border border-violet-500/30">
            <span className="text-sm font-medium text-slate-300">{selected.size} selected</span>
            <select
              value={bulkCategory}
              onChange={(e) => setBulkCategory(e.target.value)}
              className="px-3 py-2 rounded-lg border border-white/10 text-sm"
            >
              <option value="">Choose category</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
            <button
              onClick={handleBulkUpdate}
              disabled={!bulkCategory}
              className="sl-btn-primary text-white rounded-lg text-sm font-medium disabled:opacity-50"
            >
              Apply to selected
            </button>
            <button onClick={() => setSelected(new Set())} className="text-slate-400 text-sm hover:underline">
              Clear
            </button>
          </div>
        )}

        {/* Table */}
        <div className="sl-card rounded-2xl shadow-sm border border-white/10 overflow-x-auto">
          <table className="min-w-full divide-y divide-slate-200" role="grid" aria-label="Transactions">
            <thead className="bg-white/5">
              <tr>
                <th className="px-4 py-3 text-left">
                  <input type="checkbox" checked={selected.size === transactions.length && transactions.length > 0} onChange={toggleAll} />
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">Date</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">Description</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">Account</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">Category</th>
                <th className="px-6 py-3 text-right text-xs font-medium text-slate-500 uppercase">Amount</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200">
              {transactions.map((tx) => (
                <tr key={tx.id} className="hover:bg-white/5">
                  <td className="px-4 py-3">
                    <input type="checkbox" checked={selected.has(tx.id)} onChange={() => toggleSelect(tx.id)} />
                  </td>
                  <td className="px-6 py-4 text-sm text-slate-400">
                    {tx.date ? new Date(tx.date).toLocaleDateString() : '-'}
                  </td>
                  <td className="px-6 py-4 text-sm text-slate-100">
                    {tx.description || '-'}
                    {tx.is_recurring && <span className="ml-2 text-xs text-amber-600">Recurring</span>}
                  </td>
                  <td className="px-6 py-4 text-sm text-slate-400">
                    {tx.statement?.bank_account?.name || '-'}
                  </td>
                  <td className="px-6 py-4">
                    <select
                      defaultValue={tx.category?.id || ''}
                      onChange={(e) => {
                        const catId = e.target.value
                        if (catId) router.put(`/transactions/${tx.id}`, { transaction: { category_id: catId } })
                      }}
                      className="text-sm border-0 bg-transparent text-slate-300 hover:bg-white/10 rounded px-1"
                    >
                      <option value="">Uncategorized</option>
                      {categories.map((c) => (
                        <option key={c.id} value={c.id} selected={tx.category?.id === c.id}>{c.name}</option>
                      ))}
                    </select>
                  </td>
                  <td className={`px-6 py-4 text-sm text-right font-medium ${
                    tx.transaction_type === 'credit' ? 'text-emerald-600' : 'text-red-600'
                  }`}>
                    {tx.transaction_type === 'credit' ? '+' : '-'}₹
                    {Math.abs(parseFloat(tx.amount || 0)).toLocaleString('en-IN')}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {transactions.length === 0 && (
          <div className="sl-card rounded-2xl p-12 text-center border border-white/10">
            <p className="text-slate-400">No transactions found. Upload statements to get started.</p>
            <Link href="/upload" className="inline-block mt-4 text-violet-400 font-medium hover:underline">
              Upload Statement
            </Link>
          </div>
        )}
      </div>
    </DashboardLayout>
  )
}
