import { Link, useForm } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

export default function BudgetsIndex({ budgets = [], categories = [], month, year }) {
  const { data, setData, post } = useForm({ category_id: '', amount: '' })

  const monthName = month ? new Date(2000, month - 1).toLocaleString('default', { month: 'long' }) : ''

  return (
    <DashboardLayout title="Budgets">
      <div className="max-w-2xl mx-auto">
        <h2 className="text-lg font-semibold text-slate-100 mb-2">Budgets</h2>
        <p className="text-slate-400 mb-6">{monthName} {year}</p>

        <div className="space-y-4 mb-8">
          {budgets.map((b) => (
            <div key={b.category?.id} className="sl-card p-4 shadow-sm border border-white/10">
              <div className="flex justify-between items-center mb-2">
                <span className="font-medium text-slate-100">{b.category?.name}</span>
                <span className="text-sm text-slate-500">
                  ₹{b.spent.toLocaleString('en-IN')} / ₹{b.amount.toLocaleString('en-IN')}
                </span>
              </div>
              <div className="h-2 bg-white/10 rounded-full overflow-hidden">
                <div
                  className={`h-full rounded-full ${
                    b.remaining < 0 ? 'bg-red-500' : b.spent / (b.amount || 1) > 0.8 ? 'bg-amber-500' : 'bg-violet-500'
                  }`}
                  style={{ width: `${Math.min(100, (b.spent / (b.amount || 1)) * 100)}%` }}
                />
              </div>
              {b.remaining < 0 && (
                <p className="text-sm text-red-600 mt-1">Over budget by ₹{Math.abs(b.remaining).toLocaleString('en-IN')}</p>
              )}
            </div>
          ))}
        </div>

        <div className="sl-card p-6 shadow-sm border border-white/10">
          <h2 className="text-lg font-semibold text-slate-100 mb-4">Set budget</h2>
          <form
            onSubmit={(e) => {
              e.preventDefault()
              post('/budgets', {
                budget: { category_id: data.category_id, amount: data.amount },
                month,
                year,
              })
              setData({ category_id: '', amount: '' })
            }}
            className="flex gap-3"
          >
            <select
              value={data.category_id}
              onChange={(e) => setData('category_id', e.target.value)}
              className="flex-1 px-3 py-2 rounded-lg border border-white/10"
              required
            >
              <option value="">Select category</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
            <input
              type="number"
              placeholder="Amount"
              value={data.amount}
              onChange={(e) => setData('amount', e.target.value)}
              className="w-32 px-3 py-2 rounded-lg border border-white/10"
              min="0"
              step="100"
              required
            />
            <button type="submit" className="px-4 py-2 sl-btn-primary">
              Add
            </button>
          </form>
        </div>

        {budgets.length === 0 && (
          <div className="sl-card p-8 text-center border border-white/10 shadow-sm">
            <p className="text-slate-400">Set budgets to track spending by category and avoid overspending.</p>
            <p className="mt-2 text-sm text-slate-500">Add a budget above to get started.</p>
          </div>
        )}
      </div>
    </DashboardLayout>
  )
}
