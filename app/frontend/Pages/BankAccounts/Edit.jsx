import { Link, useForm } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

const getError = (errors, propErrors, field) => {
  const e = errors?.[field] ?? propErrors?.[field]
  return Array.isArray(e) ? e[0] : e
}

export default function BankAccountsEdit({ bank_account, errors: propErrors = {} }) {
  const { data, setData, put, processing, errors } = useForm({
    name: bank_account?.name || '',
    bank_name: bank_account?.bank_name || '',
    account_type: bank_account?.account_type || 'credit_card',
    last_four: bank_account?.last_four || '',
  })

  return (
    <DashboardLayout title="Edit Bank Account">
      <div className="max-w-xl mx-auto">
        <form
          onSubmit={(e) => {
            e.preventDefault()
            put(`/bank_accounts/${bank_account?.id}`)
          }}
          className="space-y-4 sl-card p-6 rounded-xl shadow-sm border border-white/10"
        >
          <div>
            <label htmlFor="name" className="block text-sm font-medium text-slate-300 mb-1">
              Account Name
            </label>
            <input
              id="name"
              type="text"
              value={data.name}
              onChange={(e) => setData('name', e.target.value)}
              placeholder="e.g. HDFC Regalia"
              className="w-full px-4 py-2 rounded-lg border border-white/10 focus:ring-2 focus:ring-violet-500"
            />
            {getError(errors, propErrors, 'name') && <p className="text-red-600 text-sm mt-1">{getError(errors, propErrors, 'name')}</p>}
          </div>

          <div>
            <label htmlFor="bank_name" className="block text-sm font-medium text-slate-300 mb-1">
              Bank Name
            </label>
            <input
              id="bank_name"
              type="text"
              value={data.bank_name}
              onChange={(e) => setData('bank_name', e.target.value)}
              placeholder="e.g. HDFC Bank"
              className="w-full px-4 py-2 rounded-lg border border-white/10 focus:ring-2 focus:ring-violet-500"
            />
            {getError(errors, propErrors, 'bank_name') && <p className="text-red-600 text-sm mt-1">{getError(errors, propErrors, 'bank_name')}</p>}
          </div>

          <div>
            <label htmlFor="account_type" className="block text-sm font-medium text-slate-300 mb-1">
              Account Type
            </label>
            <select
              id="account_type"
              value={data.account_type}
              onChange={(e) => setData('account_type', e.target.value)}
              className="w-full px-4 py-2 rounded-lg border border-white/10 focus:ring-2 focus:ring-violet-500"
            >
              <option value="credit_card">Credit Card</option>
              <option value="debit_card">Debit Card</option>
              <option value="savings">Savings Account</option>
              <option value="current">Current Account</option>
            </select>
          </div>

          <div>
            <label htmlFor="last_four" className="block text-sm font-medium text-slate-300 mb-1">
              Last 4 Digits
            </label>
            <input
              id="last_four"
              type="text"
              maxLength={4}
              value={data.last_four}
              onChange={(e) => setData('last_four', e.target.value.replace(/\D/g, ''))}
              placeholder="1234"
              className="w-full px-4 py-2 rounded-lg border border-white/10 focus:ring-2 focus:ring-violet-500"
            />
            {getError(errors, propErrors, 'last_four') && <p className="text-red-600 text-sm mt-1">{getError(errors, propErrors, 'last_four')}</p>}
          </div>

          <div className="flex gap-3">
            <button
              type="submit"
              disabled={processing}
              className="flex-1 px-6 py-3 sl-btn-primary disabled:opacity-50"
            >
              {processing ? 'Saving...' : 'Save Changes'}
            </button>
            <Link
              href={`/bank_accounts/${bank_account?.id}`}
              className="px-6 py-3 sl-card text-slate-300 font-medium rounded-xl border border-white/10 hover:bg-white/5"
            >
              Cancel
            </Link>
          </div>
        </form>
      </div>
    </DashboardLayout>
  )
}
