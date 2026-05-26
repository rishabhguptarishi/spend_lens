import { useForm } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

const COLORS = [
  '#22c55e', '#3b82f6', '#f59e0b', '#ef4444', '#8b5cf6',
  '#ec4899', '#06b6d4', '#84cc16', '#94a3b8', '#6b7280',
  '#10b981', '#f97316', '#14b8a6', '#a855f7', '#64748b',
]

export default function CategoriesNew({ errors: propErrors = {}, used_colors = [] }) {
  const used = used_colors.map((c) => c?.toLowerCase?.())
  const defaultColor = COLORS.find((c) => !used.includes(c.toLowerCase())) || COLORS[0]
  const { data, setData, post, processing, errors } = useForm({
    category: { name: '', color: defaultColor },
  })

  return (
    <DashboardLayout title="Add Category">
      <div className="max-w-xl mx-auto">
        <form
          onSubmit={(e) => {
            e.preventDefault()
            post('/categories')
          }}
          className="space-y-4 sl-card p-6 rounded-xl shadow-sm border border-white/10"
        >
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Name</label>
            <input
              type="text"
              value={data.category?.name || ''}
              onChange={(e) => setData('category', { ...data.category, name: e.target.value })}
              className="w-full px-4 py-2 rounded-lg border border-white/10 focus:ring-2 focus:ring-violet-500"
              placeholder="e.g. Food, Travel"
            />
            {(errors?.name || propErrors?.name) && (
              <p className="text-red-600 text-sm mt-1">{errors?.name || propErrors?.name}</p>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-2">Color</label>
            <div className="flex gap-2 flex-wrap">
              {COLORS.map((color) => {
                const isUsed = used.includes(color.toLowerCase())
                const isSelected = (data.category?.color || defaultColor).toLowerCase() === color.toLowerCase()
                return (
                  <button
                    key={color}
                    type="button"
                    onClick={() => !isUsed && setData('category', { ...data.category, color })}
                    disabled={isUsed}
                    title={isUsed ? 'Already used by another category' : undefined}
                    className={`w-8 h-8 rounded-full border-2 transition ${
                      isSelected ? 'border-violet-500 ring-2 ring-offset-2 ring-violet-400' : 'border-transparent'
                    } ${isUsed ? 'opacity-40 cursor-not-allowed' : 'cursor-pointer hover:ring-2 hover:ring-offset-2 hover:ring-slate-300'}`}
                    style={{ backgroundColor: color }}
                  />
                )
              })}
            </div>
            <p className="text-xs text-slate-500 mt-1">Grayed-out colors are already used by other categories.</p>
          </div>

          <button
            type="submit"
            disabled={processing}
            className="w-full sl-btn-primary px-6 py-3 disabled:opacity-50"
          >
            {processing ? 'Creating...' : 'Create Category'}
          </button>
        </form>
      </div>
    </DashboardLayout>
  )
}
