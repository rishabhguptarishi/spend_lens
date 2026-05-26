import { Link, router } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

export default function BankAccountsIndex({ bank_accounts = [] }) {
  return (
    <DashboardLayout title="Bank Accounts">
      <div className="max-w-4xl mx-auto">
        <div className="flex justify-between items-center mb-6">
          <h2 className="text-lg font-semibold text-slate-100">Bank Accounts</h2>
          <Link
            href="/bank_accounts/new"
            className="sl-btn-primary"
          >
            + Add Bank Account
          </Link>
        </div>

        {bank_accounts?.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {bank_accounts.map((account) => (
              <div
                key={account.id}
                className="sl-card p-6 shadow-sm border border-white/10 hover:border-violet-500/30 transition"
              >
                <Link href={`/bank_accounts/${account.id}`} className="block">
                  <p className="font-semibold text-slate-100">{account.name}</p>
                  <p className="text-sm text-slate-500 mt-1">{account.bank_name} •••• {account.last_four}</p>
                  {account.statements?.length > 0 && (
                    <div className="mt-2 flex items-center gap-2 flex-wrap">
                      <p className="text-xs text-slate-400">{account.statements.length} statement(s)</p>
                      {(() => {
                        const pending = account.statements.filter((s) => s.status === 'pending_overlap_review').length
                        if (!pending) return null
                        return (
                          <span className="inline-flex items-center gap-1 rounded-full border border-amber-500/40 bg-amber-500/15 px-2 py-0.5 text-[11px] font-medium text-amber-100">
                            {pending} needs review
                          </span>
                        )
                      })()}
                    </div>
                  )}
                </Link>
                <div className="flex gap-2 mt-4 pt-4 border-t border-white/10">
                  <Link
                    href={`/bank_accounts/${account.id}/edit`}
                    className="text-sm text-slate-400 hover:text-violet-400 font-medium"
                  >
                    Edit
                  </Link>
                  <button
                    type="button"
                    onClick={() => {
                      if (window.confirm('Delete this bank account and all its statements? This cannot be undone.')) {
                        router.delete(`/bank_accounts/${account.id}`)
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
          <div className="sl-card rounded-2xl p-12 text-center border border-white/10 shadow-sm">
            <p className="text-slate-400 mb-4">No bank accounts yet. Upload a statement to auto-create one, or add manually.</p>
            <div className="flex gap-4 justify-center">
              <Link
                href="/upload"
                className="inline-flex px-6 py-3 sl-btn-primary"
              >
                Upload Statement
              </Link>
              <Link
                href="/bank_accounts/new"
                className="inline-flex px-6 py-3 sl-card text-slate-300 font-medium rounded-xl border border-white/10 hover:bg-white/5"
              >
                Add Manually
              </Link>
            </div>
          </div>
        )}
      </div>
    </DashboardLayout>
  )
}
