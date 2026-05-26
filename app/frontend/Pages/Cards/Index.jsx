import { Link } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

export default function CardsIndex({ comparison = [], year, month }) {
  const totalExpenses = comparison.reduce((sum, c) => sum + (c.expenses || 0), 0)
  const maxExpenses = Math.max(...comparison.map((c) => c.expenses || 0), 1)

  return (
    <DashboardLayout title="Card Comparison">
      <div className="max-w-5xl mx-auto">
        <h2 className="text-lg font-semibold text-slate-100 mb-2">Card Comparison</h2>
        <p className="text-slate-400 mb-8">
          {month ? `Month: ${month}/${year}` : `Year: ${year}`} – Compare spending across your cards
        </p>

        {comparison.length > 0 ? (
          <>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-8">
              {comparison.map((card) => (
                <div
                  key={card.id}
                  className="sl-card rounded-2xl p-6 shadow-sm border border-white/10"
                >
                  <div className="flex items-center justify-between mb-4">
                    <div>
                      <p className="font-semibold text-slate-100">{card.name}</p>
                      <p className="text-sm text-slate-500">
                        {card.bank_name} •••• {card.last_four}
                      </p>
                    </div>
                    <span className="text-xs px-2 py-1 bg-white/10 rounded text-slate-400">
                      {card.account_type}
                    </span>
                  </div>
                  <p className="text-2xl font-bold text-red-600">
                    ₹{(card.expenses || 0).toLocaleString('en-IN')}
                  </p>
                  <p className="text-sm text-slate-500">expenses</p>
                  <div className="mt-6 h-2 bg-white/10 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-violet-500 rounded-full transition-all"
                      style={{
                        width: `${((card.expenses || 0) / maxExpenses) * 100}%`,
                      }}
                    />
                  </div>
                  <p className="text-xs text-slate-400 mt-2">
                    {card.transactions_count} transactions
                  </p>
                  <Link
                    href={`/bank_accounts/${card.id}`}
                    className="mt-4 block text-violet-400 text-sm font-medium hover:underline"
                  >
                    View details →
                  </Link>
                </div>
              ))}
            </div>

            {comparison.some((c) => Object.keys(c.by_category || {}).length > 0) && (
              <div>
                <h2 className="text-lg font-semibold text-slate-100 mb-4">Spending by Category (per card)</h2>
                <div className="space-y-6">
                  {comparison.map((card) => (
                    <div
                      key={card.id}
                      className="sl-card rounded-2xl p-6 shadow-sm border border-white/10"
                    >
                      <h3 className="font-medium text-slate-100 mb-4">{card.name}</h3>
                      <div className="space-y-2">
                        {Object.entries(card.by_category || {})
                          .sort((a, b) => b[1] - a[1])
                          .slice(0, 5)
                          .map(([cat, amount]) => (
                            <div key={cat} className="flex justify-between text-sm">
                              <span className="text-slate-400">{cat}</span>
                              <span className="font-medium text-red-600">
                                ₹{amount.toLocaleString('en-IN')}
                              </span>
                            </div>
                          ))}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </>
        ) : (
          <div className="sl-card rounded-2xl p-12 text-center border border-white/10">
            <p className="text-slate-400 mb-4">Add bank accounts and upload statements to compare.</p>
            <Link
              href="/bank_accounts/new"
              className="inline-flex px-6 py-3 sl-btn-primary"
            >
              Add Bank Account
            </Link>
          </div>
        )}
      </div>
    </DashboardLayout>
  )
}
