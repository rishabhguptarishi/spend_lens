import { Link, useForm } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

export default function ItrDocumentConfirm({ document: doc }) {
  const initial = doc.confirmed_data && Object.keys(doc.confirmed_data).length > 0
    ? doc.confirmed_data
    : doc.extracted_data || {}

  const { data, setData, patch, processing } = useForm({
    confirmed_data: initial,
    force_resync: '0',
  })

  const fields = Object.keys(initial).length > 0 ? Object.keys(initial) : ['salary', 'tds', 'interest', 'dividends']

  const setField = (key, val) => {
    setData('confirmed_data', { ...data.confirmed_data, [key]: val })
  }

  return (
    <DashboardLayout title="Confirm extraction">
      <div className="max-w-xl mx-auto">
        <Link href="/itr" className="text-sm text-violet-400 hover:underline mb-4 inline-block">
          ← ITR Assistant
        </Link>
        <h1 className="text-2xl font-bold text-slate-100 mb-2">{doc.label}</h1>
        <p className="text-sm text-slate-400 mb-6">
          Status: {doc.extraction_status} — edit and confirm extracted values.
          {['broker_pl', 'mf_cg'].includes(doc.document_type) && (
            <span className="block mt-2 text-violet-300">
              Confirming will sync transaction rows into your investment portfolio for this FY (skipped if already synced).
            </span>
          )}
        </p>

        <form
          onSubmit={(e) => {
            e.preventDefault()
            patch(`/itr/documents/${doc.id}/confirm`)
          }}
          className="space-y-4 sl-card p-6 rounded-xl border"
        >
          {fields.map((key) => (
            <div key={key}>
              <label className="block text-sm font-medium text-slate-300 mb-1">{key}</label>
              {typeof data.confirmed_data[key] === 'object' ? (
                <textarea
                  rows={4}
                  value={JSON.stringify(data.confirmed_data[key], null, 2)}
                  onChange={(e) => {
                    try {
                      setField(key, JSON.parse(e.target.value))
                    } catch {
                      setField(key, e.target.value)
                    }
                  }}
                  className="w-full px-3 py-2 border rounded-lg font-mono text-xs"
                />
              ) : (
                <input
                  type="text"
                  value={data.confirmed_data[key] ?? ''}
                  onChange={(e) => setField(key, e.target.value)}
                  className="w-full px-3 py-2 border rounded-lg"
                />
              )}
            </div>
          ))}
          {['broker_pl', 'mf_cg'].includes(doc.document_type) && (
            <label className="flex items-center gap-2 text-sm text-slate-400">
              <input
                type="checkbox"
                checked={data.force_resync === '1'}
                onChange={(e) => setData('force_resync', e.target.checked ? '1' : '0')}
              />
              Re-sync to portfolio (even if synced before)
            </label>
          )}
          <button
            type="submit"
            disabled={processing}
            className="w-full py-3 sl-btn-primary"
          >
            Confirm data
          </button>
        </form>
      </div>
    </DashboardLayout>
  )
}
