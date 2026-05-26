import { Link, useForm } from '@inertiajs/react'
import DashboardLayout from '../../../Layouts/DashboardLayout'

export default function InvestmentTransactionsNew({
  accounts = [],
  holdings = [],
  kinds = [],
  asset_classes = [],
  financial_year_start: fy,
  errors: propErrors = {},
}) {
  const { data, setData, post, processing, errors } = useForm({
    investment_transaction: {
      date: new Date().toISOString().slice(0, 10),
      kind: 'buy',
      amount: '',
      description: '',
      investment_account_id: accounts[0]?.id || '',
      investment_holding_id: '',
      asset_class: 'mutual_fund',
      financial_year_start: fy,
    },
  })

  return (
    <DashboardLayout title="Add activity">
      <div className="max-w-xl mx-auto">
        <Link href={`/investments/activity?fy=${fy}`} className="text-sm text-violet-400 hover:underline mb-4 inline-block">
          ← Activity
        </Link>
        <form
          onSubmit={(e) => {
            e.preventDefault()
            post('/investment_transactions')
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
              required
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
              min="0"
              step="0.01"
              value={data.investment_transaction.amount}
              onChange={(e) =>
                setData('investment_transaction', { ...data.investment_transaction, amount: e.target.value })
              }
              className="w-full px-4 py-2 rounded-lg border border-white/10"
              required
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Description</label>
            <input
              type="text"
              value={data.investment_transaction.description}
              onChange={(e) =>
                setData('investment_transaction', { ...data.investment_transaction, description: e.target.value })
              }
              className="w-full px-4 py-2 rounded-lg border border-white/10"
            />
          </div>
          <button type="submit" disabled={processing} className="w-full py-3 sl-btn-primary">
            Save
          </button>
        </form>
      </div>
    </DashboardLayout>
  )
}
