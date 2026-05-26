import { Link, router } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

export default function CreditCardsIndex({ credit_cards = [] }) {
  return (
    <DashboardLayout title="Credit Cards">
      <div className="max-w-4xl mx-auto">
        <div className="flex justify-between items-start mb-6">
          <div>
            <h2 className="text-lg font-semibold text-slate-100">Credit Cards</h2>
            <p className="text-slate-400 text-sm mt-1">
              Add your cards and fetch rewards from AI. Get suggestions on which card to use for each category.
            </p>
          </div>
          <div className="flex gap-3">
            <Link
              href="/credit_cards/suggestions"
              className="px-4 py-2 bg-amber-500 text-white font-medium rounded-lg hover:bg-amber-600"
            >
              Rewards Optimizer
            </Link>
            <Link
              href="/credit_cards/new"
              className="sl-btn-primary"
            >
              + Add Card
            </Link>
          </div>
        </div>

        {credit_cards?.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {credit_cards.map((card) => (
              <div
                key={card.id}
                className="sl-card p-6 shadow-sm border border-white/10 hover:border-violet-500/30 transition"
              >
                <Link href={`/credit_cards/${card.id}`} className="block">
                  <p className="font-semibold text-slate-100">{card.name}</p>
                  <p className="text-sm text-slate-500 mt-1">{card.bank_name || 'Unknown Bank'}</p>
                  {card.card_type && (
                    <span className="inline-block mt-2 text-xs px-2 py-1 bg-white/10 rounded text-slate-400">
                      {card.card_type}
                    </span>
                  )}
                  {card.rewards_structure?.category_rewards?.length > 0 && (
                    <p className="text-xs text-violet-400 mt-2">
                      {card.rewards_structure.category_rewards.length} reward categories
                    </p>
                  )}
                </Link>
                <div className="flex gap-2 mt-4 pt-4 border-t border-white/10">
                  <Link
                    href={`/credit_cards/${card.id}/edit`}
                    className="text-sm text-slate-400 hover:text-violet-400 font-medium"
                  >
                    Edit
                  </Link>
                  <button
                    type="button"
                    onClick={() => {
                      if (window.confirm('Delete this credit card?')) {
                        router.delete(`/credit_cards/${card.id}`)
                      }
                    }}
                    className="text-sm text-red-600 hover:text-red-700 font-medium"
                  >
                    Delete
                  </button>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="sl-card rounded-2xl p-12 text-center border border-white/10">
            <p className="text-slate-400 mb-4">No credit cards yet. Add your cards to get AI-powered rewards suggestions.</p>
            <div className="flex gap-4 justify-center">
              <Link
                href="/credit_cards/new"
                className="inline-flex px-6 py-3 sl-btn-primary"
              >
                Add Credit Card
              </Link>
            </div>
          </div>
        )}
      </div>
    </DashboardLayout>
  )
}
