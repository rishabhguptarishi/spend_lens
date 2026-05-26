import { Link, useForm, router } from '@inertiajs/react'
import DashboardLayout from '../../../Layouts/DashboardLayout'

export default function InvestmentAccountsEdit({ account, account_kinds = [], errors: propErrors = {} }) {
  const { data, setData, put, processing, errors } = useForm({
    investment_account: {
      name: account.name || '',
      provider: account.provider || '',
      account_kind: account.account_kind || 'other',
      notes: account.notes || '',
    },
  })

  const allErrors = { ...propErrors, ...errors }

  return (
    <DashboardLayout title="Edit account">
      <div className="max-w-xl mx-auto">
        <Link href="/investments" className="text-sm text-violet-400 hover:underline mb-4 inline-block">
          ← Portfolio
        </Link>
        <form
          onSubmit={(e) => {
            e.preventDefault()
            put(`/investment_accounts/${account.id}`)
          }}
          className="space-y-4 sl-card p-6 rounded-xl shadow-sm border border-white/10"
        >
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Name</label>
            <input
              type="text"
              value={data.investment_account.name}
              onChange={(e) => setData('investment_account', { ...data.investment_account, name: e.target.value })}
              className="w-full px-4 py-2 rounded-lg border border-white/10"
              required
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Type</label>
            <select
              value={data.investment_account.account_kind}
              onChange={(e) => setData('investment_account', { ...data.investment_account, account_kind: e.target.value })}
              className="w-full px-4 py-2 rounded-lg border border-white/10"
            >
              {account_kinds.map((k) => (
                <option key={k} value={k}>
                  {k.replace(/_/g, ' ')}
                </option>
              ))}
            </select>
          </div>
          <button type="submit" disabled={processing} className="w-full py-3 sl-btn-primary disabled:opacity-50">
            Save
          </button>
          <button
            type="button"
            onClick={() => {
              if (confirm('Delete this account and its holdings?')) {
                router.delete(`/investment_accounts/${account.id}`)
              }
            }}
            className="w-full py-2 text-red-600 text-sm hover:underline"
          >
            Delete account
          </button>
        </form>
      </div>
    </DashboardLayout>
  )
}
