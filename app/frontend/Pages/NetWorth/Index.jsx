import { Link } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

const ASSET_HINTS = {
  crypto: 'Track exchange buys/sells manually or via bank detect.',
  gold: 'SGB, ETF, or physical — record purchase cost.',
  real_estate: 'Property label + purchase price; sale flows to ITR CG.',
}

export default function NetWorthIndex({
  total_invested = 0,
  total_bank = 0,
  net_worth_approx = 0,
  bank_estimates = [],
  by_asset_class = {},
  holdings = [],
  disclaimer = '',
}) {
  return (
    <DashboardLayout title="Net worth">
      <div className="max-w-4xl mx-auto">
        <h1 className="text-2xl font-bold text-slate-100 mb-2">Net worth (approximate)</h1>
        <p className="text-slate-400 text-sm mb-6">{disclaimer}</p>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-8">
          <div className="sl-card p-6 rounded-2xl border">
            <p className="text-xs text-slate-500 uppercase">Investments (cost)</p>
            <p className="text-2xl font-bold text-violet-400">₹{total_invested.toLocaleString('en-IN')}</p>
          </div>
          <div className="sl-card p-6 rounded-2xl border">
            <p className="text-xs text-slate-500 uppercase">Banks (est.)</p>
            <p className="text-2xl font-bold text-slate-100">₹{total_bank.toLocaleString('en-IN')}</p>
          </div>
          <div className="sl-card p-6 rounded-2xl border">
            <p className="text-xs text-slate-500 uppercase">Total approx.</p>
            <p className="text-2xl font-bold text-emerald-600">₹{net_worth_approx.toLocaleString('en-IN')}</p>
          </div>
        </div>

        <h2 className="text-lg font-semibold mb-3">Bank accounts</h2>
        <div className="space-y-2 mb-8">
          {bank_estimates.map((b) => (
            <div key={b.id} className="flex justify-between sl-card px-4 py-3 rounded-lg border">
              <span>{b.name}</span>
              <span className="font-medium">₹{b.estimated_balance.toLocaleString('en-IN')}</span>
            </div>
          ))}
        </div>

        <div className="flex justify-between items-center mb-3">
          <h2 className="text-lg font-semibold">Holdings by type</h2>
          <Link href="/investment_holdings/new" className="text-sm text-violet-400 hover:underline">
            Add holding
          </Link>
        </div>
        <div className="flex flex-wrap gap-2 mb-6">
          {Object.entries(by_asset_class).map(([cls, amt]) => (
            <span key={cls} className="px-3 py-1.5 bg-white/10 rounded-full text-sm">
              {cls.replace(/_/g, ' ')}: ₹{Number(amt).toLocaleString('en-IN')}
            </span>
          ))}
        </div>

        {['crypto', 'gold', 'real_estate'].map((cls) => (
          <p key={cls} className="text-xs text-slate-500 mb-1">
            <strong>{cls}:</strong> {ASSET_HINTS[cls]}
          </p>
        ))}

        <Link href="/investments" className="inline-block mt-6 text-violet-400 hover:underline">
          Manage portfolio →
        </Link>
      </div>
    </DashboardLayout>
  )
}
