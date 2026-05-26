import { Link, router } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

export default function ItrCapitalGains({
  year,
  years = [],
  financial_year_label: fyLabel,
  rows = [],
  total_sell_amount = 0,
  estimated_stcg = 0,
  estimated_ltcg = 0,
  document_stcg = 0,
  document_ltcg = 0,
  from_tax_documents = [],
}) {
  return (
    <DashboardLayout title="Capital gains">
      <div className="max-w-5xl mx-auto">
        <div className="flex flex-wrap justify-between gap-4 mb-6">
          <div>
            <Link href="/itr" className="text-sm text-violet-400 hover:underline">← ITR Assistant</Link>
            <h1 className="text-2xl font-bold text-slate-100 mt-2">Capital gains — FY {fyLabel}</h1>
          </div>
          <div className="flex gap-2">
            <a
              href={`/itr/capital_gains/export?year=${year}`}
              className="sl-btn-primary text-white rounded-lg text-sm font-medium"
            >
              Export CSV
            </a>
          </div>
        </div>

        <div className="grid grid-cols-3 gap-4 mb-6">
          <div className="sl-card p-4 rounded-xl border">
            <p className="text-xs text-slate-500 uppercase">Total sells</p>
            <p className="text-xl font-bold">₹{total_sell_amount.toLocaleString('en-IN')}</p>
          </div>
          <div className="sl-card p-4 rounded-xl border">
            <p className="text-xs text-slate-500 uppercase">Est. STCG</p>
            <p className="text-xl font-bold text-amber-700">₹{estimated_stcg.toLocaleString('en-IN')}</p>
          </div>
          <div className="sl-card p-4 rounded-xl border">
            <p className="text-xs text-slate-500 uppercase">Est. LTCG</p>
            <p className="text-xl font-bold text-emerald-300">₹{estimated_ltcg.toLocaleString('en-IN')}</p>
          </div>
        </div>

        {(document_stcg > 0 || document_ltcg > 0) && (
          <p className="text-sm text-emerald-200 text-emerald-500/10 p-3 rounded-lg mb-4">
            From uploaded docs ({from_tax_documents.join(', ')}): STCG ₹{document_stcg.toLocaleString('en-IN')},
            LTCG ₹{document_ltcg.toLocaleString('en-IN')}
          </p>
        )}
        <p className="sl-alert-warning text-xs mb-4">
          Portfolio rows use a heuristic STCG/LTCG split — broker P&L on the ITR page is authoritative when confirmed.
        </p>

        {rows.length > 0 ? (
          <div className="sl-card border overflow-hidden">
            <table className="min-w-full text-sm">
              <thead className="bg-white/5">
                <tr>
                  <th className="px-4 py-2 text-left">Date</th>
                  <th className="px-4 py-2 text-left">Description</th>
                  <th className="px-4 py-2 text-left">Type</th>
                  <th className="px-4 py-2 text-right">Amount</th>
                  <th className="px-4 py-2 text-left">Gain</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {rows.map((r, i) => (
                  <tr key={i}>
                    <td className="px-4 py-2">{r.date}</td>
                    <td className="px-4 py-2">{r.description}</td>
                    <td className="px-4 py-2">{r.asset_class}</td>
                    <td className="px-4 py-2 text-right">₹{r.amount.toLocaleString('en-IN')}</td>
                    <td className="px-4 py-2">{r.gain_type}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-slate-400">No sell transactions this FY. Import broker data from Investments → Import.</p>
        )}
      </div>
    </DashboardLayout>
  )
}
