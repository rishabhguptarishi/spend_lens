import { useMemo } from 'react'

// Local-date formatter (avoids the toISOString UTC-shift bug for users
// outside UTC — e.g. midnight IST formats as previous day in UTC).
const fmt = (d) => {
  const yyyy = d.getFullYear()
  const mm = String(d.getMonth() + 1).padStart(2, '0')
  const dd = String(d.getDate()).padStart(2, '0')
  return `${yyyy}-${mm}-${dd}`
}

// Computes the set of presets relative to "today". Indian FY runs Apr 1 - Mar 31
// and is labelled by the start year (e.g. FY 2025-26 starts 2025-04-01).
export const buildPresets = (now = new Date()) => {
  const y = now.getFullYear()
  const m = now.getMonth() // 0-indexed

  const startOfMonth = (year, month) => new Date(year, month, 1)
  const endOfMonth = (year, month) => new Date(year, month + 1, 0)

  const fyStartYear = m >= 3 ? y : y - 1
  const fyStart = (sy) => new Date(sy, 3, 1)
  const fyEnd = (sy) => new Date(sy + 1, 2, 31)

  return [
    {
      id: 'this_month',
      label: 'This month',
      start: startOfMonth(y, m),
      end: endOfMonth(y, m),
    },
    {
      id: 'last_month',
      label: 'Last month',
      start: startOfMonth(y, m - 1),
      end: endOfMonth(y, m - 1),
    },
    {
      id: 'last_3_months',
      label: 'Last 3 months',
      start: startOfMonth(y, m - 2),
      end: endOfMonth(y, m),
    },
    {
      id: 'last_6_months',
      label: 'Last 6 months',
      start: startOfMonth(y, m - 5),
      end: endOfMonth(y, m),
    },
    {
      id: 'ytd',
      label: 'YTD',
      start: startOfMonth(y, 0),
      end: now,
    },
    {
      id: 'last_12_months',
      label: 'Last 12 months',
      start: startOfMonth(y, m - 11),
      end: endOfMonth(y, m),
    },
    {
      id: 'current_fy',
      label: `Current FY (${fyStartYear}-${String((fyStartYear + 1) % 100).padStart(2, '0')})`,
      start: fyStart(fyStartYear),
      end: fyEnd(fyStartYear),
    },
    {
      id: 'previous_fy',
      label: `Previous FY (${fyStartYear - 1}-${String(fyStartYear % 100).padStart(2, '0')})`,
      start: fyStart(fyStartYear - 1),
      end: fyEnd(fyStartYear - 1),
    },
  ]
}

// Row of preset chips for date-range filters. Clicking a chip calls
// `onApply({ start_date, end_date })` with ISO date strings (YYYY-MM-DD).
//
// Pass the currently-applied start/end (as ISO strings) so the matching chip
// is highlighted.
export default function DateRangePresets({
  onApply,
  currentStart,
  currentEnd,
  className = '',
  size = 'sm',
}) {
  const presets = useMemo(() => buildPresets(), [])

  const isActive = (p) => {
    if (!currentStart || !currentEnd) return false
    return currentStart === fmt(p.start) && currentEnd === fmt(p.end)
  }

  const sizeClasses = size === 'xs'
    ? 'px-2 py-0.5 text-[11px]'
    : 'px-2.5 py-1 text-xs'

  return (
    <div className={`flex flex-wrap gap-1.5 ${className}`}>
      {presets.map((p) => {
        const active = isActive(p)
        return (
          <button
            key={p.id}
            type="button"
            onClick={() => onApply({ start_date: fmt(p.start), end_date: fmt(p.end), preset_id: p.id })}
            className={`rounded-full font-medium border transition ${sizeClasses} ${
              active
                ? 'border-violet-500/50 bg-violet-500/15 text-violet-200'
                : 'border-white/10 bg-white/5 text-slate-300 hover:bg-white/10 hover:text-slate-100'
            }`}
          >
            {p.label}
          </button>
        )
      })}
    </div>
  )
}
