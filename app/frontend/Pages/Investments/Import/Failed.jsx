import { Link } from '@inertiajs/react'
import DashboardLayout from '../../../Layouts/DashboardLayout'

export default function InvestmentImportFailed({ batch, error }) {
  return (
    <DashboardLayout title="Import failed">
      <div className="max-w-lg mx-auto py-12">
        <h1 className="text-xl font-bold text-red-700 mb-2">Could not parse file</h1>
        <p className="text-slate-400 mb-2">{batch.filename}</p>
        <p className="text-sm sl-alert-error mb-6">{error || 'Unknown error'}</p>
        <Link href="/investments/import" className="text-violet-400 font-medium hover:underline">
          Try another file
        </Link>
      </div>
    </DashboardLayout>
  )
}
