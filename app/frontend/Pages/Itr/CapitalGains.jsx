import { Link, router } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

// Phase 4 §5.7 row 3 — capital gains UI surfaces canonical (tax-doc) vs
// heuristic figures side-by-side, with a per-source breakdown of which
// sells fed into the canonical number. Makes audit trivial: user can
// see "8 of 12 sells confirmed by broker P&L, 4 still from CSV".

const SOURCE_LABELS = {
  bank_detect: 'Bank txn (detected)',
  bank_statement: 'Bank statement',
  broker_csv: 'Broker CSV',
  broker_import: 'Broker CSV',
  zerodha_csv: 'Zerodha',
  groww_csv: 'Groww',
  generic_csv: 'CSV',
  mf_cas: 'MF CAS',
  cdsl_cas: 'CDSL CAS',
  nsdl_cas: 'NSDL CAS',
  broker_pl: 'Broker P&L',
  mf_cg: 'MF capital gains',
  manual: 'Manual',
}

function formatInr(n) {
  return `₹${Number(n || 0).toLocaleString('en-IN', { maximumFractionDigits: 2 })}`
}

export default function ItrCapitalGains({
  year,
  years = [],
  financial_year_label: fyLabel,
  rows = [],
  total_sell_amount = 0,
  superseded_sell_amount = 0,
  estimated_stcg = 0,
  estimated_ltcg = 0,
  document_stcg = 0,
  document_ltcg = 0,
  canonical_stcg = 0,
  canonical_ltcg = 0,
  canonical_source = 'heuristic',
  from_tax_documents = [],
  source_breakdown = {},
}) {
  const totalRows = rows.length
  const canonicalIsAuthoritative = canonical_source === 'tax_doc'

  return (
    <DashboardLayout title="Capital gains">
      <div className="max-w-6xl mx-auto">
        <div className="flex flex-wrap justify-between gap-4 mb-6">
          <div>
            <Link href="/itr" className="text-sm text-violet-400 hover:underline">← ITR Assistant</Link>
            <h1 className="text-2xl font-bold text-slate-100 mt-2">Capital gains — FY {fyLabel}</h1>
          </div>
          <div className="flex gap-2 items-center">
            {years.length > 0 && (
              <select
                value={year}
                onChange={(e) => router.get('/itr/capital_gains', { year: e.target.value })}
                className="sl-select"
              >
                {years.map((y) => (
                  <option key={y} value={y}>
                    FY {y}-{String((y + 1) % 100).padStart(2, '0')}
                  </option>
                ))}
              </select>
            )}
            <a
              href={`/itr/capital_gains/export?year=${year}`}
              className="sl-btn-primary text-white rounded-lg text-sm font-medium"
            >
              Export CSV
            </a>
          </div>
        </div>

        {/* Canonical figure — what the user should actually report */}
        <div className={`p-5 rounded-2xl border mb-6 ${canonicalIsAuthoritative ? 'border-emerald-500/30 bg-emerald-500/5' : 'border-amber-500/30 bg-amber-500/5'}`}>
          <div className="flex items-baseline justify-between gap-4 flex-wrap">
            <div>
              <p className="text-xs uppercase opacity-70">
                {canonicalIsAuthoritative ? 'Reportable (from uploaded tax docs)' : 'Estimate (no tax docs uploaded)'}
              </p>
              <p className="text-3xl font-bold mt-1">
                STCG {formatInr(canonical_stcg)} · LTCG {formatInr(canonical_ltcg)}
              </p>
              <p className="text-xs opacity-70 mt-2">
                {canonicalIsAuthoritative
                  ? `Source: ${from_tax_documents.join(', ')}. These are the audited figures and should be reported as-is on your ITR.`
                  : 'Upload your broker P&L statement (Zerodha/ICICI Direct/etc.) or MF capital-gains certificate to replace this estimate with the authoritative figure.'}
              </p>
            </div>
            {!canonicalIsAuthoritative && (
              <Link href="/itr" className="text-sm font-medium text-amber-300 hover:underline whitespace-nowrap">
                Upload tax docs →
              </Link>
            )}
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-4 gap-4 mb-6">
          <div className="sl-card p-4 rounded-xl border border-white/10">
            <p className="text-xs text-slate-500 uppercase">Total sells (canonical)</p>
            <p className="text-xl font-bold text-slate-100 mt-1">{formatInr(total_sell_amount)}</p>
            <p className="text-xs text-slate-500 mt-1">{totalRows} active rows</p>
          </div>
          <div className="sl-card p-4 rounded-xl border border-white/10">
            <p className="text-xs text-slate-500 uppercase">Heuristic STCG</p>
            <p className="text-xl font-bold text-amber-300 mt-1">{formatInr(estimated_stcg)}</p>
          </div>
          <div className="sl-card p-4 rounded-xl border border-white/10">
            <p className="text-xs text-slate-500 uppercase">Heuristic LTCG</p>
            <p className="text-xl font-bold text-emerald-300 mt-1">{formatInr(estimated_ltcg)}</p>
          </div>
          <div className="sl-card p-4 rounded-xl border border-white/10">
            <p className="text-xs text-slate-500 uppercase">Tax-doc STCG / LTCG</p>
            <p className="text-sm font-medium text-slate-100 mt-1">{formatInr(document_stcg)} / {formatInr(document_ltcg)}</p>
            <p className="text-xs text-slate-500 mt-1">
              {from_tax_documents.length > 0 ? from_tax_documents.join(', ') : 'no docs uploaded'}
            </p>
          </div>
        </div>

        {superseded_sell_amount > 0 && (
          <p className="sl-alert-info text-xs mb-4">
            {formatInr(superseded_sell_amount)} of legacy sells were superseded by higher-priority sources (CAS / broker P&amp;L)
            and are excluded from the canonical total. They remain in the database for audit but are NOT double-counted here.
          </p>
        )}

        {Object.keys(source_breakdown).length > 0 && (
          <div className="mb-6">
            <p className="text-xs font-medium text-slate-500 uppercase mb-2">Active sells by source</p>
            <div className="flex flex-wrap gap-2">
              {Object.entries(source_breakdown).map(([src, count]) => (
                <span key={src} className="px-3 py-1.5 rounded-full bg-white/10 text-slate-300 text-sm">
                  {SOURCE_LABELS[src] || src}: {count}
                </span>
              ))}
            </div>
          </div>
        )}

        {rows.length > 0 ? (
          <div className="sl-card border border-white/10 rounded-2xl overflow-hidden">
            <table className="min-w-full text-sm">
              <thead className="bg-white/5">
                <tr>
                  <th className="px-4 py-2 text-left text-xs text-slate-500 uppercase">Date</th>
                  <th className="px-4 py-2 text-left text-xs text-slate-500 uppercase">Description</th>
                  <th className="px-4 py-2 text-left text-xs text-slate-500 uppercase">Type</th>
                  <th className="px-4 py-2 text-right text-xs text-slate-500 uppercase">Amount</th>
                  <th className="px-4 py-2 text-left text-xs text-slate-500 uppercase">Gain</th>
                  <th className="px-4 py-2 text-left text-xs text-slate-500 uppercase">Source</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/10">
                {rows.map((r, i) => (
                  <tr key={`${r.date}-${i}`}>
                    <td className="px-4 py-2 text-slate-300">{r.date}</td>
                    <td className="px-4 py-2 text-slate-200">{r.description}</td>
                    <td className="px-4 py-2 text-slate-400 text-xs">{r.asset_class}</td>
                    <td className="px-4 py-2 text-right text-slate-100">{formatInr(r.amount)}</td>
                    <td className="px-4 py-2">
                      <span className={
                        r.gain_type === 'STCG'
                          ? 'sl-badge sl-badge-amber'
                          : r.gain_type === 'LTCG'
                            ? 'sl-badge sl-badge-emerald'
                            : 'sl-badge sl-badge-slate'
                      }>{r.gain_type}</span>
                    </td>
                    <td className="px-4 py-2 text-xs">
                      <div className="text-slate-400">{SOURCE_LABELS[r.source] || r.source}</div>
                      {(r.confirmed_by?.length || 0) > 0 && (
                        <div className="text-emerald-400 mt-0.5">+{r.confirmed_by.length} confirm{r.confirmed_by.length === 1 ? '' : 's'}</div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="sl-card rounded-2xl p-10 text-center border border-white/10">
            <p className="text-slate-400">No sell transactions this FY. Import broker data from <Link href="/investments/import" className="text-violet-400 hover:underline">Investments → Import</Link>.</p>
          </div>
        )}

        <p className="mt-6 text-xs text-slate-500">
          Active rows only — supersession from Phase 1+2 reconciliation ensures the same sell isn't counted both from your broker CSV and from
          your CDSL CAS / broker P&amp;L. Heuristic STCG/LTCG split is approximate; rely on the tax-doc figure when available.
        </p>
      </div>
    </DashboardLayout>
  )
}
