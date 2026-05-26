import { Link, useForm, router } from '@inertiajs/react'
import DashboardLayout from '../../../Layouts/DashboardLayout'

export default function InvestmentTransactionsEdit({ transaction: tx, kinds = [], errors: propErrors = {} }) {
  const { data, setData, put, processing } = useForm({
    investment_transaction: {
      date: tx.date,
      kind: tx.kind,
      amount: tx.amount,
      description: tx.description || '',
      investment_account_id: tx.investment_account_id || '',
      investment_holding_id: tx.investment_holding_id || '',
      asset_class: tx.asset_class || '',
      financial_year_start: tx.financial_year_start,
    },
  })

  return (
    <DashboardLayout title="Edit activity">
      <div className="max-w-xl mx-auto">
        <Link
          href={`/investments/activity?fy=${tx.financial_year_start}`}
          className="text-sm text-violet-400 hover:underline mb-4 inline-block"
        >
          ← Activity
        </Link>
        <form
          onSubmit={(e) => {
            e.preventDefault()
            put(`/investment_transactions/${tx.id}`)
          }}
          className="space-y-4 sl-card p-6 rounded-xl shadow-sm border border-white/10"
        >
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Date</label>
            <input
              type="date"
              value={data.investment_transaction.date}
              onChange={(e) =>
                setData('investment_transaction', { ...data.investment_transaction, date: e.target.value })
              }
              className="w-full px-4 py-2 rounded-lg border border-white/10"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Kind</label>
            <select
              value={data.investment_transaction.kind}
              onChange={(e) =>
                setData('investment_transaction', { ...data.investment_transaction, kind: e.target.value })
              }
              className="w-full px-4 py-2 rounded-lg border border-white/10"
            >
              {kinds.map((k) => (
                <option key={k} value={k}>
                  {k.replace(/_/g, ' ')}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Amount (₹)</label>
            <input
              type="number"
              value={data.investment_transaction.amount}
              onChange={(e) =>
                setData('investment_transaction', { ...data.investment_transaction, amount: e.target.value })
              }
              className="w-full px-4 py-2 rounded-lg border border-white/10"
            />
          </div>
          <button type="submit" disabled={processing} className="w-full py-3 sl-btn-primary">
            Save
          </button>
          <button
            type="button"
            onClick={() => {
              if (confirm('Delete this activity?')) router.delete(`/investment_transactions/${tx.id}`)
            }}
            className="w-full py-2 text-red-600 text-sm"
          >
            Delete
          </button>
        </form>
      </div>
    </DashboardLayout>
  )
}
