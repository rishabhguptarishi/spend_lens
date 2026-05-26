import { Link, useForm, usePage } from '@inertiajs/react'
import { useState } from 'react'
import DashboardLayout from '../../Layouts/DashboardLayout'
import PreferCsvHint from './PreferCsvHint'

export default function StatementUploadsNew({ bank_accounts = [] }) {
  const { flash } = usePage().props
  const [drag, setDrag] = useState(false)
  const [fileType, setFileType] = useState(null)
  const { data, setData, post, processing, errors } = useForm({
    file: null,
    replace: false,
  })

  const isPdf = fileType === 'pdf'

  return (
    <DashboardLayout title="Upload Statement">
      <div className="max-w-2xl mx-auto">
        <h2 className="text-lg font-semibold text-slate-100 mb-2">Upload Statement</h2>
        {flash?.alert && (
          <div className="mb-4 p-4 rounded-lg sl-alert-error">
            {flash.alert}
          </div>
        )}
        {flash?.notice && (
          <div className="mb-4 p-4 rounded-lg sl-alert-success">
            {flash.notice}
          </div>
        )}
        <p className="text-slate-400 mb-6">
          Just upload your CSV or PDF. We'll auto-detect your bank, create the account, and extract all transactions.
        </p>

        <PreferCsvHint />

        <form
          onSubmit={(e) => {
            e.preventDefault()
            if (!data.file) return
            post('/upload', { forceFormData: true })
          }}
          className="space-y-4 sl-card p-8 rounded-2xl shadow-sm border border-white/10"
        >
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">
              Statement File (CSV or PDF)
            </label>
            <div
              onDragOver={(e) => { e.preventDefault(); setDrag(true) }}
              onDragLeave={() => setDrag(false)}
              onDrop={(e) => {
                e.preventDefault()
                setDrag(false)
                const f = e.dataTransfer.files[0]
                if (f && /\.(csv|pdf)$/i.test(f.name)) {
                  setData('file', f)
                  setFileType(f.name.toLowerCase().endsWith('.pdf') ? 'pdf' : 'csv')
                }
              }}
              className={`w-full px-4 py-8 rounded-xl border-2 border-dashed text-center transition ${
                drag ? 'bg-violet-500 border-violet-500 bg-violet-500/10' : 'border-white/10 hover:border-white/20'
              }`}
            >
              <input
                type="file"
                accept=".csv,.pdf"
                onChange={(e) => {
                  const f = e.target.files[0]
                  setData('file', f)
                  setFileType(f && f.name.toLowerCase().endsWith('.pdf') ? 'pdf' : 'csv')
                }}
                className="hidden"
                id="file-input"
              />
              <label htmlFor="file-input" className="cursor-pointer">
                {data.file ? (
                  <span className="text-violet-400 font-medium">{data.file.name}</span>
                ) : (
                  <span className="text-slate-400">Drop file here or click to browse</span>
                )}
              </label>
            </div>
            {errors?.file && <p className="text-red-600 text-sm mt-1">{errors.file}</p>}
            {isPdf && (
              <p className="mt-2 text-xs text-amber-300/80">
                ⓘ PDF uploaded — if parsing produces wrong numbers, try the CSV export instead (see "Prefer CSV" hint above).
              </p>
            )}
          </div>

          <label className="flex items-center gap-2 cursor-pointer">
            <input
              type="checkbox"
              checked={data.replace}
              onChange={(e) => setData('replace', e.target.checked)}
              className="rounded border-white/20 text-violet-400 focus:ring-violet-500"
            />
            <span className="text-sm text-slate-400">Replace existing statement if same month/year</span>
          </label>

          <button
            type="submit"
            disabled={processing || !data.file}
            className="w-full sl-btn-primary px-6 py-3 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {processing ? 'Processing...' : 'Upload & Parse'}
          </button>
        </form>

        <p className="mt-4 text-sm text-slate-500">
          Bank account and statement period are auto-detected. No manual setup needed.
        </p>

        {bank_accounts?.length > 0 && (
          <div className="mt-8">
            <p className="text-sm text-slate-400 mb-2">Or add to existing account:</p>
            <Link
              href="/bank_accounts"
              className="text-violet-400 font-medium hover:underline"
            >
              Choose from your accounts →
            </Link>
          </div>
        )}
      </div>
    </DashboardLayout>
  )
}
