import { Link, useForm } from '@inertiajs/react'
import DashboardLayout from '../../../Layouts/DashboardLayout'

const SOURCE_LABELS = {
  zerodha: 'Zerodha (tradebook / tax P&L CSV)',
  groww: 'Groww (stocks CSV)',
  hdfc_sec: 'HDFC Securities CSV',
  mf_cas: 'MF CAS (PDF or text export)',
  cdsl_cas: 'CDSL CAS — demat + MF folios (unlocked PDF)',
  epf_passbook: 'EPF UAN passbook',
  nps_statement: 'NPS Protean statement',
  amc_direct: 'AMC direct folio statement',
  generic_csv: 'Generic CSV (column mapper)',
}

const SOURCE_HINTS = {
  cdsl_cas:
    'Upload the unlocked CDSL Consolidated Account Statement PDF. We import MF folio transactions with real amounts and a current snapshot of equity holdings, grouped per broker (each broker becomes its own account).',
  mf_cas: 'Upload the unlocked MF CAS PDF or text export. Transactions across AMCs will be imported.',
  epf_passbook: 'Upload an EPFO member passbook PDF/text export. We import employee/employer contributions, interest, and withdrawals against the UAN.',
  nps_statement: 'Upload an NPS Protean transaction statement PDF/text export. We import Tier I/II contributions, redemptions, and units against the PRAN.',
  amc_direct: 'Upload an AMC folio statement PDF/text export. We import direct-plan purchase, SIP, redemption, and IDCW rows by folio.',
}

export default function InvestmentImportNew({
  sources = [],
  accounts = [],
  financial_year_start: fy,
  years = [],
  large_import_bytes = 512_000,
}) {
  const { data, setData, post, processing } = useForm({
    source: 'zerodha',
    financial_year_start: fy,
    investment_account_id: '',
    file: null,
    column_mapping: { date: '', description: '', amount: '', kind: '', asset_class: 'stock' },
  })

  return (
    <DashboardLayout title="Import investments">
      <div className="max-w-xl mx-auto">
        <Link href="/investments" className="text-sm text-violet-400 hover:underline mb-4 inline-block">
          ← Portfolio
        </Link>
        <h1 className="text-2xl font-bold text-slate-100 mb-2">Import broker / MF data</h1>
        <p className="text-slate-400 text-sm mb-6">
          Upload CSV or MF CAS PDF. Preview before importing.
          {large_import_bytes > 0 && (
            <span className="block mt-1">
              Files over ~{Math.round(large_import_bytes / 1024)}KB or 400+ rows parse in the background.
            </span>
          )}
        </p>

        <form
          onSubmit={(e) => {
            e.preventDefault()
            post('/investments/import', { forceFormData: true })
          }}
          className="space-y-4 sl-card p-6 rounded-xl border border-white/10"
        >
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Source</label>
            <select
              value={data.source}
              onChange={(e) => setData('source', e.target.value)}
              className="w-full px-3 py-2 rounded-lg border border-white/10"
            >
              {sources.map((s) => (
                <option key={s} value={s}>
                  {SOURCE_LABELS[s] || s}
                </option>
              ))}
            </select>
            {SOURCE_HINTS[data.source] && (
              <p className="mt-2 text-xs text-slate-400">{SOURCE_HINTS[data.source]}</p>
            )}
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Financial year</label>
            <select
              value={data.financial_year_start}
              onChange={(e) => setData('financial_year_start', Number(e.target.value))}
              className="w-full px-3 py-2 rounded-lg border border-white/10"
            >
              {years.map((y) => (
                <option key={y} value={y}>
                  FY {y}-{String((y + 1) % 100).padStart(2, '0')}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Link to account (optional)</label>
            <select
              value={data.investment_account_id}
              onChange={(e) => setData('investment_account_id', e.target.value)}
              className="w-full px-3 py-2 rounded-lg border border-white/10"
            >
              <option value="">Auto-create</option>
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </div>
          {data.source === 'generic_csv' && (
            <div className="text-sm space-y-2 p-3 bg-white/5 rounded-lg">
              <p className="font-medium text-slate-300">Column names in your CSV (optional)</p>
              {['date', 'description', 'amount', 'kind'].map((col) => (
                <input
                  key={col}
                  placeholder={col}
                  value={data.column_mapping[col] || ''}
                  onChange={(e) =>
                    setData('column_mapping', { ...data.column_mapping, [col]: e.target.value })
                  }
                  className="w-full px-2 py-1 border rounded"
                />
              ))}
            </div>
          )}
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">File</label>
            <input
              type="file"
              accept=".csv,.pdf,.txt"
              onChange={(e) => setData('file', e.target.files[0])}
              className="w-full text-sm"
              required
            />
          </div>
          <button
            type="submit"
            disabled={processing || !data.file}
            className="w-full py-3 sl-btn-primary disabled:opacity-50"
          >
            {processing ? 'Parsing…' : 'Preview import'}
          </button>
        </form>
      </div>
    </DashboardLayout>
  )
}
