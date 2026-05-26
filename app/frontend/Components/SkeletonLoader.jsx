export function SkeletonCard() {
  return (
    <div className="sl-card p-6 animate-pulse">
      <div className="h-12 w-12 rounded-lg bg-white/10" />
      <div className="mt-4 h-4 w-32 rounded bg-white/10" />
      <div className="mt-2 h-8 w-24 rounded bg-white/10" />
    </div>
  )
}

export function SkeletonTable({ rows = 5 }) {
  return (
    <div className="sl-table-wrap animate-pulse">
      <div className="border-b border-white/10 p-4">
        <div className="flex gap-4">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="h-4 flex-1 rounded bg-white/10" />
          ))}
        </div>
      </div>
      <div className="divide-y divide-white/10">
        {Array.from({ length: rows }).map((_, i) => (
          <div key={i} className="flex gap-4 p-4">
            {[1, 2, 3, 4].map((j) => (
              <div key={j} className="h-4 flex-1 rounded bg-white/10" />
            ))}
          </div>
        ))}
      </div>
    </div>
  )
}
