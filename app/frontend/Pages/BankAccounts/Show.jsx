import { Link, router } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'
import StatementStatusBadge from '../../Components/StatementStatusBadge'

export default function BankAccountsShow({ bank_account, statements }) {
  const pendingReviewCount = (statements || []).filter((s) => s.status === 'pending_overlap_review').length
  return (
    <DashboardLayout title={bank_account?.name || 'Bank Account'}>
      <div className="max-w-4xl mx-auto">
        <div className="mb-8 flex justify-between items-start">
          <div>
            <h2 className="text-lg font-semibold text-slate-100">{bank_account.name}</h2>
            <p className="text-slate-400">{bank_account.bank_name} •••• {bank_account.last_four}</p>
          </div>
          <div className="flex gap-3">
            <Link
              href={`/bank_accounts/${bank_account.id}/edit`}
              className="px-4 py-2 bg-white/10 text-slate-300 font-medium rounded-lg hover:bg-white/15"
            >
              Edit
            </Link>
            <button
              type="button"
              onClick={() => {
                if (window.confirm('Delete this bank account and all its statements? This cannot be undone.')) {
                  router.delete(`/bank_accounts/${bank_account.id}`)
                }
              }}
              className="px-4 py-2 sl-alert-error text-red-300 font-medium rounded-lg hover:bg-red-500/20"
            >
              Delete
            </button>
          </div>
        </div>

        {pendingReviewCount > 0 && (
          <div className="mb-4 flex items-center justify-between gap-3 rounded-xl border border-amber-500/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
            <span>
              {pendingReviewCount} statement{pendingReviewCount === 1 ? '' : 's'} waiting on your decision after an overlap was detected.
            </span>
            <Link
              href={`/statements/${(statements || []).find((s) => s.status === 'pending_overlap_review')?.id}/overlap_review`}
              className="px-3 py-1.5 rounded-lg bg-amber-500/20 hover:bg-amber-500/30 border border-amber-500/40 text-amber-100 font-medium"
            >
              Review now
            </Link>
          </div>
        )}

        <div className="flex justify-between items-center mb-6">
          <h3 className="text-base font-semibold text-slate-100">Statements</h3>
          <Link
            href={`/bank_accounts/${bank_account.id}/statements/new`}
            className="sl-btn-primary"
          >
            + Upload Statement
          </Link>
        </div>

        {statements?.length > 0 ? (
          <div className="sl-card rounded-2xl shadow-sm border border-white/10 overflow-hidden">
            <table className="min-w-full">
              <thead className="bg-white/5">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">Period</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">Status</th>
                  <th className="px-6 py-3 text-right text-xs font-medium text-slate-500 uppercase">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/10">
                {statements.map((stmt) => (
                  <tr key={stmt.id}>
                    <td className="px-6 py-4 text-slate-100">
                      {stmt.period_start && stmt.period_end
                        ? `${stmt.period_start} → ${stmt.period_end}`
                        : `${stmt.month}/${stmt.year}`}
                    </td>
                    <td className="px-6 py-4">
                      <StatementStatusBadge status={stmt.status} statementId={stmt.id} />
                    </td>
                    <td className="px-6 py-4 text-right space-x-3">
                      {stmt.status === 'pending_overlap_review' && (
                        <Link
                          href={`/statements/${stmt.id}/overlap_review`}
                          className="text-amber-300 hover:text-amber-200 font-medium"
                        >
                          Review
                        </Link>
                      )}
                      <Link
                        href={`/bank_accounts/${bank_account.id}/statements/${stmt.id}`}
                        className="text-violet-400 hover:text-violet-300 font-medium"
                      >
                        View
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="sl-card rounded-2xl p-12 text-center border border-white/10">
            <p className="text-slate-400 mb-4">No statements yet. Upload your first statement to get started.</p>
            <Link
              href={`/bank_accounts/${bank_account.id}/statements/new`}
              className="inline-flex px-6 py-3 sl-btn-primary"
            >
              Upload Statement
            </Link>
          </div>
        )}
      </div>
    </DashboardLayout>
  )
}
