import { Link, router } from '@inertiajs/react'
import { useEffect, useRef } from 'react'
import DashboardLayout from '../../Layouts/DashboardLayout'
import StatementStatusBadge from '../../Components/StatementStatusBadge'

export default function StatementsShow({ statement, transactions, categories = [] }) {
  const bank_account = statement?.bank_account
  const isProcessing = statement?.status === 'processing'
  const needsReview = statement?.status === 'pending_overlap_review'
  const pollTimerRef = useRef(null)

  useEffect(() => {
    if (!isProcessing) return

    const tick = () => {
      router.reload({
        only: ['statement', 'transactions'],
        preserveScroll: true,
        preserveState: true,
      })
    }

    pollTimerRef.current = setInterval(tick, 30000)
    return () => {
      if (pollTimerRef.current) clearInterval(pollTimerRef.current)
    }
  }, [isProcessing])

  return (
    <DashboardLayout title={`Statement ${statement?.month}/${statement?.year}`}>
      <div className="max-w-5xl mx-auto">
        <div className="mb-6 flex items-start justify-between gap-4">
          <div>
            <h2 className="text-lg font-semibold text-slate-100">
              Statement {statement?.month}/{statement?.year}
            </h2>
            <p className="text-slate-400">{bank_account?.bank_name}</p>
          </div>
          {statement?.status && (
            <StatementStatusBadge status={statement.status} statementId={statement.id} linkOnReview={false} />
          )}
        </div>

        {needsReview && (
          <div className="mb-6 flex items-center justify-between gap-3 rounded-xl border border-amber-500/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
            <span>
              This upload's period overlaps with existing statements. Parsing is paused until you choose how to proceed.
            </span>
            <Link
              href={`/statements/${statement.id}/overlap_review`}
              className="px-3 py-1.5 rounded-lg bg-amber-500/20 hover:bg-amber-500/30 border border-amber-500/40 text-amber-100 font-medium"
            >
              Resolve
            </Link>
          </div>
        )}

        {transactions?.length > 0 ? (
          <div className="sl-card rounded-2xl shadow-sm border border-white/10 overflow-hidden">
            <table className="min-w-full divide-y divide-slate-200">
              <thead className="bg-white/5">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">Date</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">Description</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">Category</th>
                  <th className="px-6 py-3 text-right text-xs font-medium text-slate-500 uppercase">Amount</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-200">
                {transactions.map((tx) => (
                  <tr key={tx.id} className="hover:bg-white/5">
                    <td className="px-6 py-4 text-sm text-slate-400">
                      {tx.date ? new Date(tx.date).toLocaleDateString() : '-'}
                    </td>
                    <td className="px-6 py-4 text-sm text-slate-100">{tx.description || '-'}</td>
                    <td className="px-6 py-4 text-sm">
                      <select
                        defaultValue={tx.category?.id || ''}
                        onChange={(e) => {
                          const catId = e.target.value
                          if (catId) router.put(`/transactions/${tx.id}`, { transaction: { category_id: catId } })
                        }}
                        className="border-0 bg-transparent text-slate-300 hover:bg-white/10 rounded px-1 text-sm"
                      >
                        <option value="">Uncategorized</option>
                        {categories.map((c) => (
                          <option key={c.id} value={c.id}>{c.name}</option>
                        ))}
                      </select>
                      {tx.is_recurring && <span className="ml-1 text-xs text-amber-600">↻</span>}
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
        ) : (
          <div className="sl-card rounded-2xl p-12 text-center border border-white/10">
            {isProcessing ? (
              <p className="text-slate-300">
                Parsing your statement… transactions will appear here automatically once it's done.
              </p>
            ) : (
              <p className="text-slate-400">No transactions found. Upload a CSV or PDF file to parse transactions.</p>
            )}
          </div>
        )}
      </div>
    </DashboardLayout>
  )
}
