import { Link } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

export default function CategoriesIndex({ categories = [] }) {
  return (
    <DashboardLayout title="Categories">
      <div className="max-w-4xl mx-auto">
        <div className="flex justify-between items-center mb-8">
          <h2 className="text-lg font-semibold text-slate-100">Categories</h2>
          <Link
            href="/categories/new"
            className="sl-btn-primary"
          >
            + Add Category
          </Link>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {categories.map((cat) => (
            <div
              key={cat.id}
              className="group sl-card p-4 shadow-sm border border-white/10 hover:border-violet-500/40 hover:bg-white/5 transition flex items-center justify-between gap-3"
            >
              <Link
                href={`/transactions?category_id=${cat.id}`}
                className="flex items-center gap-3 flex-1 min-w-0"
                aria-label={`View transactions in ${cat.name}`}
              >
                <div
                  className="w-4 h-4 rounded-full shrink-0"
                  style={{ backgroundColor: cat.color || '#94a3b8' }}
                />
                <div className="min-w-0">
                  <p className="font-medium text-slate-100 truncate group-hover:text-violet-200 transition">
                    {cat.name}
                  </p>
                  <p className="text-sm text-slate-500">
                    {cat.transactions_count || 0} transaction{cat.transactions_count === 1 ? '' : 's'}
                  </p>
                </div>
              </Link>
              <div className="flex gap-3 shrink-0">
                <Link
                  href={`/categories/${cat.id}/edit`}
                  className="text-violet-400 hover:text-violet-300 text-sm font-medium"
                >
                  Edit
                </Link>
                <Link
                  href={`/categories/${cat.id}`}
                  method="delete"
                  as="button"
                  className="text-red-400 hover:text-red-300 text-sm font-medium"
                >
                  Delete
                </Link>
              </div>
            </div>
          ))}
        </div>

        {categories.length === 0 && (
          <div className="sl-card rounded-2xl p-12 text-center border border-white/10">
            <p className="text-slate-400 mb-4">No categories yet. Add your first category.</p>
            <Link
              href="/categories/new"
              className="inline-flex px-6 py-3 sl-btn-primary"
            >
              Add Category
            </Link>
          </div>
        )}
      </div>
    </DashboardLayout>
  )
}
