import { Link, useForm, router } from '@inertiajs/react'
import DashboardLayout from '../../../Layouts/DashboardLayout'

export default function InvestmentHoldingsEdit({
  holding,
  accounts = [],
  asset_classes = [],
  errors: propErrors = {},
}) {
  const { data, setData, put, processing, errors } = useForm({
    investment_holding: {
      investment_account_id: holding.investment_account_id,
      asset_class: holding.asset_class,
      name: holding.name,
      symbol: holding.symbol || '',
      units: holding.units || '',
      invested_amount: holding.invested_amount || '',
    },
  })

  return (
    <DashboardLayout title="Edit holding">
      <div className="max-w-xl mx-auto">
        <Link href="/investments" className="text-sm text-violet-400 hover:underline mb-4 inline-block">
          ← Portfolio
        </Link>
        <form
          onSubmit={(e) => {
            e.preventDefault()
            put(`/investment_holdings/${holding.id}`)
          }}
          className="space-y-4 sl-card p-6 rounded-xl shadow-sm border border-white/10"
        >
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Account</label>
            <select
              value={data.investment_holding.investment_account_id}
              onChange={(e) =>
                setData('investment_holding', { ...data.investment_holding, investment_account_id: e.target.value })
              }
              className="w-full px-4 py-2 rounded-lg border border-white/10"
            >
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Name</label>
            <input
              type="text"
              value={data.investment_holding.name}
              onChange={(e) => setData('investment_holding', { ...data.investment_holding, name: e.target.value })}
              className="w-full px-4 py-2 rounded-lg border border-white/10"
              required
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Invested amount (₹)</label>
            <input
              type="number"
              value={data.investment_holding.invested_amount}
              onChange={(e) =>
                setData('investment_holding', { ...data.investment_holding, invested_amount: e.target.value })
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
              if (confirm('Remove this holding?')) router.delete(`/investment_holdings/${holding.id}`)
            }}
            className="w-full py-2 text-red-600 text-sm"
          >
            Delete holding
          </button>
        </form>
      </div>
    </DashboardLayout>
  )
}
