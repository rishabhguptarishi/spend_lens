import { Link, useForm } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

const CARD_TYPES = [
  { value: 'rewards', label: 'Rewards' },
  { value: 'cashback', label: 'Cashback' },
  { value: 'travel', label: 'Travel' },
  { value: 'fuel', label: 'Fuel' },
  { value: 'lifestyle', label: 'Lifestyle' },
  { value: 'premium', label: 'Premium' },
]

const getError = (errors, propErrors, field) => {
  const e = errors?.[field] ?? propErrors?.[field]
  return Array.isArray(e) ? e[0] : e
}

export default function CreditCardsEdit({ credit_card, errors: propErrors = {} }) {
  const { data, setData, put, processing, errors } = useForm({
    name: credit_card?.name || '',
    bank_name: credit_card?.bank_name || '',
    card_type: credit_card?.card_type || 'rewards',
    annual_fee: credit_card?.annual_fee || '',
    fee_waiver_spend: credit_card?.fee_waiver_spend || '',
    notes: credit_card?.notes || '',
  })

  return (
    <DashboardLayout title="Edit Credit Card">
      <div className="max-w-xl mx-auto">
        <form
          onSubmit={(e) => {
            e.preventDefault()
            put(`/credit_cards/${credit_card?.id}`)
          }}
          className="space-y-4 sl-card p-6 rounded-xl shadow-sm border border-white/10"
        >
          <div>
            <label htmlFor="name" className="block text-sm font-medium text-slate-300 mb-1">Card Name *</label>
            <input
              id="name"
              type="text"
              value={data.name}
              onChange={(e) => setData('name', e.target.value)}
              placeholder="e.g. HDFC Regalia"
              className="w-full px-4 py-2 rounded-lg border border-white/10 focus:ring-2 focus:ring-violet-500"
            />
            {getError(errors, propErrors, 'name') && (
              <p className="text-red-600 text-sm mt-1">{getError(errors, propErrors, 'name')}</p>
            )}
          </div>

          <div>
            <label htmlFor="bank_name" className="block text-sm font-medium text-slate-300 mb-1">Bank / Issuer</label>
            <input
              id="bank_name"
              type="text"
              value={data.bank_name}
              onChange={(e) => setData('bank_name', e.target.value)}
              className="w-full px-4 py-2 rounded-lg border border-white/10 focus:ring-2 focus:ring-violet-500"
            />
          </div>

          <div>
            <label htmlFor="card_type" className="block text-sm font-medium text-slate-300 mb-1">Card Type</label>
            <select
              id="card_type"
              value={data.card_type}
              onChange={(e) => setData('card_type', e.target.value)}
              className="w-full px-4 py-2 rounded-lg border border-white/10 focus:ring-2 focus:ring-violet-500"
            >
              {CARD_TYPES.map((t) => (
                <option key={t.value} value={t.value}>{t.label}</option>
              ))}
            </select>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label htmlFor="annual_fee" className="block text-sm font-medium text-slate-300 mb-1">Annual Fee (₹)</label>
              <input
                id="annual_fee"
                type="number"
                min="0"
                step="0.01"
                value={data.annual_fee}
                onChange={(e) => setData('annual_fee', e.target.value)}
                className="w-full px-4 py-2 rounded-lg border border-white/10 focus:ring-2 focus:ring-violet-500"
              />
            </div>
            <div>
              <label htmlFor="fee_waiver_spend" className="block text-sm font-medium text-slate-300 mb-1">Fee Waiver Spend (₹)</label>
              <input
                id="fee_waiver_spend"
                type="number"
                min="0"
                step="0.01"
                value={data.fee_waiver_spend}
                onChange={(e) => setData('fee_waiver_spend', e.target.value)}
                className="w-full px-4 py-2 rounded-lg border border-white/10 focus:ring-2 focus:ring-violet-500"
              />
            </div>
          </div>

          <div>
            <label htmlFor="notes" className="block text-sm font-medium text-slate-300 mb-1">Notes</label>
            <textarea
              id="notes"
              rows={2}
              value={data.notes}
              onChange={(e) => setData('notes', e.target.value)}
              className="w-full px-4 py-2 rounded-lg border border-white/10 focus:ring-2 focus:ring-violet-500"
            />
          </div>

          <div className="flex gap-3">
            <button
              type="submit"
              disabled={processing}
              className="flex-1 px-6 py-3 sl-btn-primary disabled:opacity-50"
            >
              {processing ? 'Saving...' : 'Save'}
            </button>
            <Link
              href={`/credit_cards/${credit_card?.id}`}
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
