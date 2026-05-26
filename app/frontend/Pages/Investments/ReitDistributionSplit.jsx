// Phase 4 §5.7 row "REIT/InvIT distribution UI".
//
// REIT/InvIT distributions are a TAX TRAP: only the dividend component
// is taxable as IFOS; the interest piece is taxable separately; the
// CAPITAL-RETURN piece is NOT taxable BUT it REDUCES your cost basis.
// Most retail investors don't know this and end up with an under-cost
// basis at sale time. We surface the split explicitly so the user
// understands their effective cost basis.
//
// Data source: when the user uploads a Broker P&L or REIT statement,
// the parser populates instrument.metadata.distributions = [
//   { date, total, dividend, interest, capital_return }, ...
// ]. When absent (default), we show the educational notice + empty
// state. This is the §5.5 "graceful degradation" UI contract.

function formatInr(n) {
  return `₹${Number(n || 0).toLocaleString('en-IN', { maximumFractionDigits: 2 })}`
}

export default function ReitDistributionSplit({ instrument }) {
  const distributions = instrument.metadata?.distributions || []
  const totals = distributions.reduce(
    (acc, d) => ({
      total: acc.total + Number(d.total || 0),
      dividend: acc.dividend + Number(d.dividend || 0),
      interest: acc.interest + Number(d.interest || 0),
      capital_return: acc.capital_return + Number(d.capital_return || 0),
    }),
    { total: 0, dividend: 0, interest: 0, capital_return: 0 },
  )

  const adjustedCost = Number(instrument.cost_basis || 0) - totals.capital_return

  return (
    <div className="border border-amber-500/30 bg-amber-500/5 rounded-lg p-4">
      <div className="flex items-start gap-3">
        <div className="text-amber-400 mt-0.5">⚠</div>
        <div className="flex-1">
          <p className="text-sm font-medium text-amber-100">REIT / InvIT distribution split</p>
          <p className="text-xs text-amber-100/80 mt-1 mb-3">
            Distributions from REITs and InvITs have <strong>three tax-distinct components</strong>. The capital-return piece is non-taxable BUT
            reduces your cost basis — so your effective cost (and therefore your eventual capital gain on sale) is different from what you paid in.
          </p>

          {distributions.length === 0 ? (
            <p className="text-xs text-slate-400 italic">
              No distribution breakdowns yet. Upload your broker P&amp;L or the REIT issuer's annual statement to see the 3-way split.
            </p>
          ) : (
            <>
              <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 mb-3">
                <div className="border border-white/10 rounded p-2">
                  <p className="text-xs text-slate-500 uppercase">Total received</p>
                  <p className="text-sm font-medium text-slate-100">{formatInr(totals.total)}</p>
                </div>
                <div className="border border-emerald-500/30 rounded p-2 bg-emerald-500/5">
                  <p className="text-xs text-emerald-200/70 uppercase">Dividend (IFOS)</p>
                  <p className="text-sm font-medium text-emerald-200">{formatInr(totals.dividend)}</p>
                </div>
                <div className="border border-violet-500/30 rounded p-2 bg-violet-500/5">
                  <p className="text-xs text-violet-200/70 uppercase">Interest</p>
                  <p className="text-sm font-medium text-violet-200">{formatInr(totals.interest)}</p>
                </div>
                <div className="border border-amber-500/30 rounded p-2 bg-amber-500/10">
                  <p className="text-xs text-amber-200/70 uppercase">Capital return</p>
                  <p className="text-sm font-medium text-amber-200">{formatInr(totals.capital_return)}</p>
                </div>
              </div>

              <div className="border-t border-white/10 pt-3">
                <p className="text-xs text-slate-400">
                  Paid-in cost: {formatInr(instrument.cost_basis)} &nbsp;·&nbsp;
                  Capital return received: {formatInr(totals.capital_return)} &nbsp;·&nbsp;
                  <strong className="text-amber-200">Effective cost basis: {formatInr(adjustedCost)}</strong>
                </p>
              </div>

              <details className="mt-3">
                <summary className="text-xs text-violet-400 cursor-pointer hover:underline">View per-distribution breakdown</summary>
                <table className="mt-2 w-full text-xs">
                  <thead>
                    <tr className="text-slate-500">
                      <th className="text-left py-1">Date</th>
                      <th className="text-right py-1">Total</th>
                      <th className="text-right py-1">Dividend</th>
                      <th className="text-right py-1">Interest</th>
                      <th className="text-right py-1">Capital return</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-white/5">
                    {distributions.map((d, idx) => (
                      <tr key={`${d.date}-${idx}`} className="text-slate-300">
                        <td className="py-1">{d.date}</td>
                        <td className="text-right py-1">{formatInr(d.total)}</td>
                        <td className="text-right py-1 text-emerald-300">{formatInr(d.dividend)}</td>
                        <td className="text-right py-1 text-violet-300">{formatInr(d.interest)}</td>
                        <td className="text-right py-1 text-amber-300">{formatInr(d.capital_return)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </details>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
