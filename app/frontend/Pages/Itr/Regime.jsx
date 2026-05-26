import { Link, router } from '@inertiajs/react'
import { useState } from 'react'
import DashboardLayout from '../../Layouts/DashboardLayout'

export default function ItrRegime({ year, years = [], regime = {} }) {
  const [deduction80c, setDeduction80c] = useState(regime.deductions_used?.['80c'] || '')
  const [deduction80d, setDeduction80d] = useState(regime.deductions_used?.['80d'] || '')
  const [hra, setHra] = useState(regime.deductions_used?.hra || '')

  const recalc = (e) => {
    e.preventDefault()
    router.get('/itr/regime', {
      year,
      deduction_80c: deduction80c,
      deduction_80d: deduction80d,
      hra,
    })
  }

  return (
    <DashboardLayout title="Tax regime compare">
      <div className="max-w-3xl mx-auto">
        <Link href="/itr" className="text-sm text-violet-400 hover:underline mb-4 inline-block">
          ← ITR Assistant
        </Link>
        <h1 className="text-2xl font-bold text-slate-100 mb-6">Old vs new regime</h1>

        <form onSubmit={recalc} className="mb-8 grid grid-cols-1 sm:grid-cols-3 gap-3">
          <input
            type="number"
            placeholder="80C (max 1.5L)"
            value={deduction80c}
            onChange={(e) => setDeduction80c(e.target.value)}
            className="px-3 py-2 border rounded-lg"
          />
          <input
            type="number"
            placeholder="80D"
            value={deduction80d}
            onChange={(e) => setDeduction80d(e.target.value)}
            className="px-3 py-2 border rounded-lg"
          />
          <input
            type="number"
            placeholder="HRA exemption"
            value={hra}
            onChange={(e) => setHra(e.target.value)}
            className="px-3 py-2 border rounded-lg"
          />
          <button type="submit" className="sm:col-span-3 py-2 bg-slate-800 text-white rounded-lg font-medium">
            Recalculate
          </button>
        </form>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
          <div className="sl-card p-6 rounded-2xl border">
            <p className="text-sm text-slate-500 uppercase">New regime</p>
            <p className="text-3xl font-bold text-violet-400 mt-2">
              ₹{regime.new_regime?.total?.toLocaleString('en-IN')}
            </p>
            <p className="text-xs text-slate-500 mt-2">Taxable ₹{regime.new_regime?.taxable?.toLocaleString('en-IN')}</p>
          </div>
          <div className="sl-card p-6 rounded-2xl border">
            <p className="text-sm text-slate-500 uppercase">Old regime</p>
            <p className="text-3xl font-bold text-slate-100 mt-2">
              ₹{regime.old_regime?.total?.toLocaleString('en-IN')}
            </p>
            <p className="text-xs text-slate-500 mt-2">Taxable ₹{regime.old_regime?.taxable?.toLocaleString('en-IN')}</p>
          </div>
        </div>

        {regime.likely_better && (
          <p className="p-4 rounded-xl bg-violet-500/10 text-violet-200">
            Likely better: <strong>{regime.likely_better} regime</strong> (saves ~₹{regime.savings?.toLocaleString('en-IN')} vs other)
          </p>
        )}
        <p className="mt-4 text-xs text-slate-500">{regime.disclaimer}</p>
      </div>
    </DashboardLayout>
  )
}
