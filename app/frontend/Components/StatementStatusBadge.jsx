import { Link } from '@inertiajs/react'

const STATUS_STYLES = {
  pending: {
    label: 'Pending',
    className: 'border-slate-500/30 bg-slate-500/10 text-slate-300',
  },
  processing: {
    label: 'Parsing…',
    className: 'border-amber-500/30 bg-amber-500/10 text-amber-200',
    pulse: true,
  },
  pending_overlap_review: {
    label: 'Needs review',
    className: 'border-amber-500/50 bg-amber-500/15 text-amber-100',
  },
  parsed: {
    label: 'Parsed',
    className: 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200',
  },
  failed: {
    label: 'Failed',
    className: 'border-red-500/30 bg-red-500/10 text-red-200',
  },
}

const PILL_BASE = 'inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium whitespace-nowrap'

export default function StatementStatusBadge({ status, statementId, linkOnReview = true }) {
  const def = STATUS_STYLES[status] || STATUS_STYLES.pending
  const className = `${PILL_BASE} ${def.className}`

  const content = (
    <>
      {def.pulse && (
        <span className="relative flex h-2 w-2">
          <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-amber-300 opacity-75" />
          <span className="relative inline-flex h-2 w-2 rounded-full bg-amber-400" />
        </span>
      )}
      {def.label}
    </>
  )

  if (status === 'pending_overlap_review' && linkOnReview && statementId) {
    return (
      <Link
        href={`/statements/${statementId}/overlap_review`}
        className={`${className} hover:bg-amber-500/20 transition`}
        title="Resolve overlap"
      >
        {content}
      </Link>
    )
  }

  return <span className={className}>{content}</span>
}
