import { useForm, usePage } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

export default function StatementsNew({ bank_account }) {
  const { ai_provider_label = 'AI' } = usePage().props
  const { data, setData, post, processing, errors } = useForm({
    statement: {
      month: new Date().getMonth() + 1,
      year: new Date().getFullYear(),
      file: null,
    },
  })

  const handleSubmit = (e) => {
    e.preventDefault()
    post(`/bank_accounts/${bank_account.id}/statements`)
  }

  return (
    <DashboardLayout title={`Upload Statement - ${bank_account?.name || ''}`}>
      <div className="max-w-xl mx-auto">
        <h2 className="text-lg font-semibold text-slate-100 mb-2">Upload Statement</h2>
        <p className="text-slate-400 mb-6">{bank_account.name} - {bank_account.bank_name}</p>

        <form onSubmit={handleSubmit} className="space-y-4 sl-card p-6 rounded-xl shadow-sm border border-white/10">
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Month</label>
            <select
              value={data.statement?.month}
              onChange={(e) => setData('statement', { ...data.statement, month: parseInt(e.target.value) })}
              className="w-full px-4 py-2 rounded-lg border border-white/10"
            >
              {[1,2,3,4,5,6,7,8,9,10,11,12].map((m) => (
                <option key={m} value={m}>
                  {new Date(2000, m - 1).toLocaleString('default', { month: 'long' })}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Year</label>
            <input
              type="number"
              value={data.statement?.year}
              onChange={(e) => setData('statement', { ...data.statement, year: parseInt(e.target.value) })}
              min="2020"
              max="2030"
              className="w-full px-4 py-2 rounded-lg border border-white/10"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Statement File (CSV or PDF)</label>
            <input
              type="file"
              accept=".csv,.pdf"
              onChange={(e) => setData('statement', { ...data.statement, file: e.target.files[0] })}
              className="w-full px-4 py-2 rounded-lg border border-white/10"
            />
            {errors?.file && <p className="text-red-600 text-sm mt-1">{errors.file}</p>}
          </div>

          <button
            type="submit"
            disabled={processing}
            className="w-full sl-btn-primary px-6 py-3 disabled:opacity-50"
          >
            {processing ? 'Uploading...' : 'Upload'}
          </button>
        </form>

        <p className="mt-4 text-sm text-slate-500">
          Supported: CSV, PDF. Uses layered hybrid parsing (regex + AI validation). {ai_provider_label} assistance optional but recommended.
        </p>
      </div>
    </DashboardLayout>
  )
}
