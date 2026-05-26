import { Link } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

export default function CreditCardsSuggestions({
  suggestions = [],
  summary = '',
  spending_by_category = {},
  message = '',
  portfolio_gaps = [],
  high_spend_categories = [],
  fee_analysis = [],
}) {
  const spendingEntries = Object.entries(spending_by_category || {}).sort((a, b) => b[1] - a[1])

  return (
    <DashboardLayout title="Rewards Optimizer">
      <div className="max-w-4xl mx-auto space-y-8">
        <div>
          <h2 className="text-lg font-semibold text-slate-100 mb-2">Rewards Optimizer</h2>
          <p className="text-slate-400">
            Statement-driven recommendations: which card to use, fee worthiness, and portfolio gaps.
          </p>
        </div>

        {message && (
          <div className="sl-alert-warning">{message}</div>
        )}

        {fee_analysis?.length > 0 && (
          <div className="sl-card rounded-2xl shadow-sm border border-white/10 overflow-hidden">
            <h2 className="text-lg font-semibold text-slate-100 px-6 py-4 bg-white/5 border-b border-white/10">
              Annual fee analysis
            </h2>
            <div className="divide-y divide-white/10">
              {fee_analysis.map((card) => (
                <div key={card.card_id} className="px-6 py-4">
                  <div className="flex flex-wrap justify-between gap-2 mb-2">
                    <div>
                      <p className="font-semibold text-slate-100">{card.card_name}</p>
                      <p className="text-sm text-slate-500">{card.bank_name}</p>
                    </div>
                    <span
                      className={`text-xs font-medium px-2 py-1 rounded ${
                        card.worth_it ? 'bg-emerald-100 text-emerald-800' : 'bg-red-100 text-red-800'
                      }`}
                    >
                      {card.worth_it ? 'Worth it' : 'Review fee'}
                    </span>
                  </div>
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm mb-2">
                    <div>
                      <p className="text-slate-500">Annual fee</p>
                      <p className="font-medium">₹{Number(card.annual_fee || 0).toLocaleString('en-IN')}</p>
                    </div>
                    <div>
                      <p className="text-slate-500">Est. rewards/yr</p>
                      <p className="font-medium text-emerald-600">
                        ₹{Number(card.estimated_annual_rewards || 0).toLocaleString('en-IN')}
                      </p>
                    </div>
                    <div>
                      <p className="text-slate-500">Net value</p>
                      <p className={`font-medium ${card.net_value >= 0 ? 'text-emerald-600' : 'text-red-600'}`}>
                        ₹{Number(card.net_value || 0).toLocaleString('en-IN')}
                      </p>
                    </div>
                    {card.fee_waiver_spend > 0 && (
                      <div>
                        <p className="text-slate-500">Fee waiver at</p>
                        <p className="font-medium">₹{Number(card.fee_waiver_spend).toLocaleString('en-IN')}</p>
                      </div>
                    )}
                  </div>
                  <p className="text-sm text-slate-400">{card.recommendation}</p>
                </div>
              ))}
            </div>
          </div>
        )}

        {portfolio_gaps?.length > 0 && (
          <div className="sl-card rounded-2xl p-6 shadow-sm border border-white/10">
            <h2 className="text-lg font-semibold text-slate-100 mb-4">Portfolio gaps</h2>
            <p className="text-sm text-slate-400 mb-4">
              Categories where you spend a lot but your cards may not reward you well.
            </p>
            <div className="space-y-4">
              {portfolio_gaps.map((gap) => (
                <div key={gap.category} className="p-4 rounded-lg border border-amber-500/30 bg-amber-500/10">
                  <div className="flex justify-between items-start gap-2">
                    <p className="font-medium text-amber-100">{gap.category}</p>
                    <span className="text-sm font-medium text-amber-200/90">
                      ₹{Number(gap.amount_spent).toLocaleString('en-IN')} spent
                    </span>
                  </div>
                  <p className="text-sm text-slate-300 mt-2">{gap.suggestion}</p>
                  {gap.best_existing_card && (
                    <p className="text-xs text-slate-400 mt-1">
                      Best existing: {gap.best_existing_card} ({gap.effective_reward_pct}% effective)
                    </p>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {summary && (
          <div className="bg-violet-500/10 rounded-2xl p-6 border border-violet-500/30">
            <h3 className="text-sm font-medium text-violet-300 uppercase mb-2">AI summary</h3>
            <p className="text-violet-100">{summary}</p>
          </div>
        )}

        {suggestions.length > 0 && (
          <div className="sl-card rounded-2xl shadow-sm border border-white/10 overflow-hidden">
            <h2 className="text-lg font-semibold text-slate-100 px-6 py-4 bg-white/5">
              Card to use by category (AI)
            </h2>
            <div className="overflow-x-auto">
              <table className="min-w-full">
                <thead className="bg-white/5">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">Category</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">Card</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">Reason</th>
                    <th className="px-6 py-3 text-right text-xs font-medium text-slate-500 uppercase">Use up to</th>
                    <th className="px-6 py-3 text-right text-xs font-medium text-slate-500 uppercase">Est. rewards</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-200">
                  {suggestions.map((s, i) => (
                    <tr key={i}>
                      <td className="px-6 py-4 font-medium text-slate-100">{s.category}</td>
                      <td className="px-6 py-4 text-slate-300">{s.card}</td>
                      <td className="px-6 py-4 text-slate-400 text-sm">{s.reason}</td>
                      <td className="px-6 py-4 text-right text-slate-400">
                        {s.use_up_to ? `₹${Number(s.use_up_to).toLocaleString('en-IN')}` : '—'}
                      </td>
                      <td className="px-6 py-4 text-right font-medium text-violet-400">
                        {s.estimated_rewards != null ? `₹${Number(s.estimated_rewards).toLocaleString('en-IN')}` : '—'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {high_spend_categories?.length > 0 && spendingEntries.length === 0 && (
          <div className="sl-card rounded-2xl p-6 shadow-sm border border-white/10">
            <h2 className="text-lg font-semibold text-slate-100 mb-4">High-spend categories</h2>
            <div className="space-y-2">
              {high_spend_categories.map(({ category, amount }) => (
                <div key={category} className="flex justify-between">
                  <span className="text-slate-300">{category}</span>
                  <span className="font-medium">₹{Number(amount).toLocaleString('en-IN')}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {spendingEntries.length > 0 && (
          <div className="sl-card rounded-2xl p-6 shadow-sm border border-white/10">
            <h2 className="text-lg font-semibold text-slate-100 mb-4">Your spending (last 3 months)</h2>
            <div className="space-y-2">
              {spendingEntries.slice(0, 15).map(([cat, amt]) => (
                <div key={cat} className="flex justify-between">
                  <span className="text-slate-300">{cat}</span>
                  <span className="font-medium text-slate-100">₹{Number(amt).toLocaleString('en-IN')}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {suggestions.length === 0 && !message && fee_analysis.length === 0 && (
          <div className="sl-card rounded-2xl p-12 text-center border border-white/10">
            <p className="text-slate-400 mb-4">
              Add credit cards, fetch their rewards, and upload statements to get recommendations.
            </p>
            <div className="flex gap-4 justify-center flex-wrap">
              <Link href="/credit_cards/new" className="px-6 py-3 sl-btn-primary">
                Add card
              </Link>
              <Link href="/upload" className="px-6 py-3 sl-card text-slate-300 font-medium rounded-xl border border-white/10 hover:bg-white/5">
                Upload statement
              </Link>
              <Link href="/ai" className="px-6 py-3 bg-amber-500 text-white font-medium rounded-xl hover:bg-amber-600">
                Ask Savvy
              </Link>
            </div>
          </div>
        )}
      </div>
    </DashboardLayout>
  )
}
