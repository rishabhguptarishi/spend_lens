import { Link, router } from '@inertiajs/react'
import { useEffect } from 'react'
import DashboardLayout from '../../../Layouts/DashboardLayout'

export default function InvestmentImportProcessing({ batch }) {
  useEffect(() => {
    if (batch.status !== 'processing') return undefined

    const timer = setInterval(() => {
      router.visit(`/investments/import/${batch.id}`, { preserveScroll: true })
    }, 2500)

    return () => clearInterval(timer)
  }, [batch.id, batch.status])

  return (
    <DashboardLayout title="Parsing import">
      <div className="max-w-lg mx-auto text-center py-16">
        <div className="inline-block h-10 w-10 border-4 border-blue-600 border-t-transparent rounded-full animate-spin mb-6" />
        <h1 className="text-xl font-bold text-slate-100 mb-2">Parsing {batch.filename}</h1>
        <p className="text-slate-400 text-sm mb-6">
          Large files run in the background. This page refreshes automatically every few seconds.
        </p>
        <Link href="/investments/import" className="text-sm text-violet-400 hover:underline">
          ← Back to import
        </Link>
      </div>
    </DashboardLayout>
  )
}
