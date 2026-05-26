import { Link, router } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

export default function CreditCardsShow({ credit_card }) {
  const rewards = credit_card?.rewards_structure || {}
  const categoryRewards = rewards.category_rewards || []
  const specialOffers = rewards.special_offers || []
  const baseReward = rewards.base_reward || {}

  return (
    <DashboardLayout title={credit_card?.name || 'Credit Card'}>
      <div className="max-w-2xl mx-auto">
        <div className="mb-8 flex justify-between items-start">
          <div>
            <h2 className="text-lg font-semibold text-slate-100">{credit_card?.name}</h2>
          <p className="text-slate-400">{credit_card?.bank_name || 'Unknown Bank'}</p>
          {credit_card?.card_type && (
            <span className="inline-block mt-2 text-xs px-2 py-1 bg-white/10 rounded text-slate-400">
              {credit_card.card_type}
            </span>
          )}
          {(credit_card?.annual_fee?.to_f > 0 || credit_card?.fee_waiver_spend?.to_f > 0) && (
            <div className="mt-4 flex gap-6 text-sm text-slate-400">
              {credit_card.annual_fee?.to_f > 0 && (
                <span>Annual fee: ₹{Number(credit_card.annual_fee).toLocaleString('en-IN')}</span>
              )}
              {credit_card.fee_waiver_spend?.to_f > 0 && (
                <span>Fee waiver: ₹{Number(credit_card.fee_waiver_spend).toLocaleString('en-IN')} spend</span>
              )}
            </div>
          )}
          </div>
          <div className="flex gap-3">
            <Link
              href={`/credit_cards/${credit_card?.id}/edit`}
              className="px-4 py-2 bg-white/10 text-slate-300 font-medium rounded-lg hover:bg-white/15"
            >
              Edit
            </Link>
            <button
              type="button"
              onClick={() => {
                if (window.confirm('Fetch rewards from AI? This will overwrite existing rewards.')) {
                  router.post(`/credit_cards/${credit_card?.id}/fetch_rewards`)
                }
              }}
              className="px-4 py-2 bg-amber-500 text-white font-medium rounded-lg hover:bg-amber-600"
            >
              Fetch Rewards (AI)
            </button>
            <button
              type="button"
              onClick={() => {
                if (window.confirm('Delete this credit card?')) {
                  router.delete(`/credit_cards/${credit_card?.id}`)
                }
              }}
              className="px-4 py-2 sl-alert-error text-red-300 font-medium rounded-lg hover:bg-red-500/20"
            >
              Delete
            </button>
          </div>
        </div>

        {categoryRewards.length > 0 ? (
          <div className="sl-card rounded-2xl p-6 shadow-sm border border-white/10 mb-6">
            <h2 className="text-lg font-semibold text-slate-100 mb-4">Category Rewards</h2>
            <div className="space-y-3">
              {categoryRewards.map((r, i) => (
                <div key={i} className="flex justify-between items-start py-2 border-b border-white/10 last:border-0">
                  <div>
                    <p className="font-medium text-slate-100">{r.category}</p>
                    <p className="text-sm text-slate-500">{r.description || `${r.rate}%`}</p>
                  </div>
                  <div className="text-right">
                    <p className="font-medium text-violet-400">
                      {r.rate}{r.rate_type === 'percent' ? '%' : ' pts/₹100'}
                    </p>
                    {r.cap_amount && (
                      <p className="text-xs text-slate-500">Cap ₹{r.cap_amount}/{r.cap_period || 'month'}</p>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        ) : (
          <div className="rounded-2xl p-6 border border-amber-500/30 bg-amber-500/10 mb-6">
            <p className="text-amber-100">
              No rewards data. Click &quot;Fetch Rewards (AI)&quot; to populate from AI.
            </p>
          </div>
        )}

        {Object.keys(baseReward).length > 0 && (
          <div className="sl-card rounded-2xl p-6 shadow-sm border border-white/10 mb-6">
            <h2 className="text-lg font-semibold text-slate-100 mb-2">Base Reward</h2>
            <p className="text-slate-400">{baseReward.description || `${baseReward.rate} pts/₹100`}</p>
          </div>
        )}

        {specialOffers.length > 0 && (
          <div className="sl-card rounded-2xl p-6 shadow-sm border border-white/10 mb-6">
            <h2 className="text-lg font-semibold text-slate-100 mb-4">Special Offers</h2>
            <ul className="list-disc list-inside space-y-1 text-slate-400">
              {specialOffers.map((offer, i) => (
                <li key={i}>{offer}</li>
              ))}
            </ul>
          </div>
        )}

        {credit_card?.notes && (
          <div className="sl-card rounded-2xl p-6 shadow-sm border border-white/10">
            <h2 className="text-lg font-semibold text-slate-100 mb-2">Notes</h2>
            <p className="text-slate-400 whitespace-pre-wrap">{credit_card.notes}</p>
          </div>
        )}

        <div className="mt-8">
          <Link
            href="/credit_cards/suggestions"
            className="inline-flex px-6 py-3 bg-amber-500 text-white font-medium rounded-xl hover:bg-amber-600"
          >
            Get Rewards Suggestions →
          </Link>
        </div>
      </div>
    </DashboardLayout>
  )
}
