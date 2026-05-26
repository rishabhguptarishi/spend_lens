import { useState } from 'react'

// Phase 4 §5.7 row 5 — "Prefer CSV over PDF" hint with per-bank
// instructions. CSV is the cleanest input we can get; PDFs are
// per-bank-version brittle (which is what Phase 3 hardened). Educating
// users to download CSV when their bank offers it is the single biggest
// lever to reduce parse failures.
//
// Instructions kept short and copy-pasteable. Order by retail share so
// the most-likely banks appear first.

const BANK_INSTRUCTIONS = [
  {
    bank: 'HDFC Bank',
    steps: [
      'Login → Accounts → Click account number',
      'Click "Download" → "E-statements"',
      'Choose date range → Select "Excel" / "CSV"',
    ],
    note: 'HDFC web sometimes labels CSV as ".xls" — that\'s still tabular and we parse it fine.',
  },
  {
    bank: 'ICICI Bank',
    steps: [
      'Login → Bank Accounts → "View Statement"',
      'Select date range',
      'Click "Detailed Statement" → "Download as Excel/CSV"',
    ],
    note: 'iMobile Pay app: Accounts → 3-dot menu → "Download Statement" → CSV.',
  },
  {
    bank: 'SBI',
    steps: [
      'Login → My Accounts → Account Statement',
      'Pick FROM/TO dates',
      'Format: "CSV file" → "Go"',
    ],
    note: 'SBI YONO app does not support CSV — use sbiyono.in or sbionline.in on the web.',
  },
  {
    bank: 'Axis Bank',
    steps: [
      'Login → Accounts → Account Statement',
      'Select period',
      'Choose "Excel" / "CSV" format and download',
    ],
  },
  {
    bank: 'Kotak',
    steps: [
      'Login (web) → Accounts → "Detailed Statement"',
      'Choose date range',
      '"Export" → "CSV / Excel"',
    ],
    note: 'Kotak\'s "Quick Statement" only gives PDF — go to "Detailed Statement" for CSV.',
  },
  {
    bank: 'Yes / IDFC First / Federal / IndusInd / PNB / Canara / BoB',
    steps: [
      'Login (web) → Account Statement / Transaction History',
      'Select period → "Download as Excel / CSV"',
    ],
    note: 'Most retail banks have CSV under the "advanced" or "detailed" statement option.',
  },
]

export default function PreferCsvHint() {
  const [expanded, setExpanded] = useState(false)

  return (
    <div className="mb-6 rounded-xl border border-violet-500/30 bg-violet-500/5 p-4">
      <div className="flex items-start gap-3">
        <span className="text-violet-400 text-lg mt-0.5">★</span>
        <div className="flex-1">
          <p className="text-sm font-medium text-violet-100">Prefer CSV over PDF when your bank offers it</p>
          <p className="text-xs text-violet-100/80 mt-1">
            CSVs are 100% reliable — no per-bank layout quirks, no scanned-PDF OCR issues, no "amount column in the wrong place".
            PDF parsing works for 4 banks today (HDFC, ICICI, SBI, Axis) and will keep expanding, but CSV always wins.
          </p>
          <button
            type="button"
            className="mt-2 text-xs font-medium text-violet-300 hover:underline"
            onClick={() => setExpanded(!expanded)}
          >
            {expanded ? 'Hide bank instructions ↑' : 'Show how to download CSV from each bank ↓'}
          </button>

          {expanded && (
            <div className="mt-4 grid grid-cols-1 md:grid-cols-2 gap-3">
              {BANK_INSTRUCTIONS.map((b) => (
                <div key={b.bank} className="border border-violet-500/20 rounded-lg p-3 bg-violet-500/[0.03]">
                  <p className="font-medium text-violet-100 text-sm">{b.bank}</p>
                  <ol className="mt-2 text-xs text-violet-100/80 list-decimal list-inside space-y-0.5">
                    {b.steps.map((s, i) => (
                      <li key={i}>{s}</li>
                    ))}
                  </ol>
                  {b.note && (
                    <p className="mt-2 text-xs text-violet-200/60 italic">{b.note}</p>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
