import { Link, useForm } from '@inertiajs/react'
import DashboardLayout from '../../../Layouts/DashboardLayout'

export default function InvestmentHoldingsNew({
  accounts = [],
  asset_classes = [],
  errors: propErrors = {},
}) {
  const { data, setData, post, processing, errors } = useForm({
    investment_holding: {
      investment_account_id: accounts[0]?.id || '',
      asset_class: 'mutual_fund',
      name: '',
      symbol: '',
      units: '',
      invested_amount: '',
    },
  })

  const allErrors = { ...propErrors, ...errors }

  return (
    <DashboardLayout title="Add holding">
      <div className="max-w-xl mx-auto">
        <Link href="/investments" className="text-sm text-violet-400 hover:underline mb-4 inline-block">
          ← Portfolio
        </Link>
        {accounts.length === 0 && (
          <p className="mb-4 sl-alert-warning text-sm">
            Create an{' '}
            <Link href="/investment_accounts/new" className="font-medium underline">
              investment account
            </Link>{' '}
            first.
          </p>
        )}
        <form
          onSubmit={(e) => {
            e.preventDefault()
            post('/investment_holdings')
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
              required
            >
              <option value="">Select account</option>
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Asset type</label>
            <select
              value={data.investment_holding.asset_class}
              onChange={(e) =>
                setData('investment_holding', { ...data.investment_holding, asset_class: e.target.value })
              }
              className="w-full px-4 py-2 rounded-lg border border-white/10"
            >
              {asset_classes.map((c) => (
                <option key={c} value={c}>
                  {c.replace(/_/g, ' ')}
                  {['crypto', 'gold', 'real_estate'].includes(c) ? ' ★' : ''}
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
              placeholder="Scheme / stock / FD label"
              required
            />
            {allErrors.name && <p className="text-red-600 text-sm mt-1">{allErrors.name}</p>}
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Invested amount (₹)</label>
            <input
              type="number"
              min="0"
              step="0.01"
              value={data.investment_holding.invested_amount}
              onChange={(e) =>
                setData('investment_holding', { ...data.investment_holding, invested_amount: e.target.value })
              }
              className="w-full px-4 py-2 rounded-lg border border-white/10"
            />
          </div>
          <button type="submit" disabled={processing || accounts.length === 0} className="w-full py-3 sl-btn-primary disabled:opacity-50">
            Add holding
          </button>
        </form>
      </div>
    </DashboardLayout>
  )
}
