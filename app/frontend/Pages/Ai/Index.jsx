import { useState } from 'react'
import DashboardLayout from '../../Layouts/DashboardLayout'
import {
  SparklesIcon,
  CreditCardIcon,
  WrenchScrewdriverIcon,
  CheckCircleIcon,
  XCircleIcon,
  BoltIcon,
} from '@heroicons/react/24/outline'

const EXPENSE_QUESTIONS = [
  'How much did I spend on food and dining last month?',
  'Top 5 spending categories — and how I can trim them',
  'Compare my spending this month vs last month',
  'Find duplicate or unusual charges in the last 60 days',
  'Am I spending more than I earn?',
  'What are my recurring payments?',
]

const SEARCH_QUESTIONS = [
  'Show all my Swiggy transactions',
  'Find salary credits in the last 6 months',
  'List UPI payments above ₹5000',
  'What did I spend on Amazon this year?',
]

const CARD_QUESTIONS = [
  'Which credit card should I use for dining?',
  'Best card for my top 3 categories?',
  'Is my annual fee worth it based on my spending?',
  'Which card gives the best rewards for travel?',
]

const ITR_QUESTIONS = [
  'Which ITR form should I file this year?',
  'What gaps remain in my filing readiness?',
  'Explain my AIS reconciliation mismatches',
  'Old vs new regime — which is better for me?',
  'What capital gains do I need to report?',
]

const AGENTIC_ACTION_QUESTIONS = [
  'Find my uncategorised transactions and suggest categories',
  'Set up a monthly food budget based on my recent spend',
  'Create a rule to auto-categorise Swiggy as Food & Dining',
]

const formatCurrency = (v) => `₹${Number(v || 0).toLocaleString('en-IN')}`

function ToolTrail({ trail }) {
  const [open, setOpen] = useState(false)
  if (!trail || trail.length === 0) return null

  return (
    <div className="mt-3">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="inline-flex items-center gap-1.5 text-xs text-slate-500 hover:text-slate-300"
      >
        <WrenchScrewdriverIcon className="h-3.5 w-3.5" />
        {open ? 'Hide' : 'Show'} agent steps ({trail.length})
      </button>
      {open && (
        <ol className="mt-2 space-y-1.5 text-xs">
          {trail.map((step, i) => (
            <li
              key={i}
              className="rounded-lg border border-white/5 bg-white/5 px-3 py-2 text-slate-400"
            >
              <span className="text-violet-300 font-medium">{step.name}</span>
              {step.args && Object.keys(step.args).length > 0 && (
                <span className="ml-1 text-slate-500">{JSON.stringify(step.args)}</span>
              )}
              {step.result_preview && (
                <div className="mt-1 text-[11px] text-slate-500 line-clamp-2 break-all">
                  {step.result_preview}
                </div>
              )}
            </li>
          ))}
        </ol>
      )}
    </div>
  )
}

function ProposalCard({ proposal, onApply, onReject, status }) {
  const isApplying = status === 'applying'
  const isApplied = status === 'applied'
  const isRejected = status === 'rejected'
  const errored = status?.error

  const kindLabel = {
    recategorize_transactions: 'Recategorise transactions',
    create_budget: 'Create budget',
    create_category_rule: 'Create category rule',
    create_category: 'Create category',
  }[proposal.kind] || proposal.kind

  return (
    <div
      className={`rounded-xl border p-4 ${
        isApplied
          ? 'border-emerald-500/40 bg-emerald-500/10'
          : isRejected
            ? 'border-white/5 bg-white/5 opacity-60'
            : 'border-violet-500/40 bg-violet-500/10'
      }`}
    >
      <div className="flex items-start gap-2">
        <BoltIcon
          className={`h-5 w-5 shrink-0 mt-0.5 ${
            isApplied ? 'text-emerald-300' : 'text-violet-300'
          }`}
        />
        <div className="flex-1 min-w-0">
          <p className="text-xs font-medium uppercase tracking-wide text-violet-300">
            {kindLabel}
          </p>
          <p className="font-medium text-slate-100 mt-0.5">{proposal.summary}</p>
          {proposal.reason && (
            <p className="text-sm text-slate-400 mt-1">{proposal.reason}</p>
          )}
          {proposal.sample_transactions && proposal.sample_transactions.length > 0 && (
            <ul className="mt-2 text-xs text-slate-400 space-y-0.5 max-h-32 overflow-y-auto">
              {proposal.sample_transactions.map((t, i) => (
                <li key={i} className="truncate">
                  {t.date} · {t.description} · {formatCurrency(t.amount)}
                </li>
              ))}
              {proposal.transaction_count > proposal.sample_transactions.length && (
                <li className="text-slate-500">
                  …and {proposal.transaction_count - proposal.sample_transactions.length} more
                </li>
              )}
            </ul>
          )}
        </div>
      </div>

      {errored && (
        <p className="mt-3 text-sm text-red-300">{status.error}</p>
      )}

      <div className="mt-4 flex gap-2 justify-end">
        {!isApplied && !isRejected && (
          <>
            <button
              type="button"
              onClick={onReject}
              disabled={isApplying}
              className="px-3 py-1.5 text-sm rounded-lg border border-white/10 text-slate-300 hover:bg-white/5 disabled:opacity-50"
            >
              <XCircleIcon className="h-4 w-4 inline-block mr-1 -mt-0.5" />
              Reject
            </button>
            <button
              type="button"
              onClick={onApply}
              disabled={isApplying}
              className="sl-btn-primary px-3 py-1.5 text-sm"
            >
              <CheckCircleIcon className="h-4 w-4 inline-block mr-1 -mt-0.5" />
              {isApplying ? 'Applying…' : 'Apply'}
            </button>
          </>
        )}
        {isApplied && (
          <span className="text-sm text-emerald-300 font-medium">
            <CheckCircleIcon className="h-4 w-4 inline-block mr-1 -mt-0.5" />
            Applied
          </span>
        )}
        {isRejected && (
          <span className="text-sm text-slate-500">Rejected</span>
        )}
      </div>
    </div>
  )
}

function ChatTurn({ turn, onApplyProposal, onRejectProposal }) {
  return (
    <div className="space-y-2">
      <div className="flex items-start gap-2">
        <div className="h-7 w-7 rounded-full bg-slate-700 text-slate-200 text-xs flex items-center justify-center font-semibold shrink-0">
          You
        </div>
        <div className="flex-1 text-slate-200 whitespace-pre-wrap">{turn.question}</div>
      </div>
      <div className="flex items-start gap-2 pl-9">
        <div className="flex-1">
          {turn.error ? (
            <div className="sl-alert-error">{turn.error}</div>
          ) : (
            <>
              <div className="sl-card p-4">
                <div className="text-slate-100 whitespace-pre-wrap">{turn.answer}</div>
                <ToolTrail trail={turn.tool_trail} />
                <div className="mt-3 text-[11px] text-slate-500">
                  {turn.agentic ? (
                    <>Agent mode · {turn.steps} step{turn.steps === 1 ? '' : 's'} · {turn.model || turn.provider}</>
                  ) : (
                    <>Single-shot · {turn.provider}</>
                  )}
                </div>
              </div>
              {turn.proposals && turn.proposals.length > 0 && (
                <div className="mt-3 space-y-2">
                  {turn.proposals.map((p, i) => (
                    <ProposalCard
                      key={`${turn.id}-prop-${i}`}
                      proposal={p}
                      status={turn.proposalStatus?.[i]}
                      onApply={() => onApplyProposal(turn.id, i)}
                      onReject={() => onRejectProposal(turn.id, i)}
                    />
                  ))}
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}

export default function AiIndex({
  categories = [],
  credit_cards = [],
  itr_years = [],
  current_fy,
  ai_provider = 'ollama',
  agentic_enabled = false,
  agentic_writes_enabled = false,
}) {
  const params = new URLSearchParams(typeof window !== 'undefined' ? window.location.search : '')
  const [mode, setMode] = useState(params.get('mode') === 'itr' ? 'itr' : 'spending')
  const [itrYear, setItrYear] = useState(Number(params.get('year')) || current_fy)
  const [question, setQuestion] = useState('')
  const [turns, setTurns] = useState([])
  const [loading, setLoading] = useState(false)

  const [bestCategory, setBestCategory] = useState(categories[0] || '')
  const [bestMerchant, setBestMerchant] = useState('')
  const [bestAmount, setBestAmount] = useState('')
  const [bestResult, setBestResult] = useState(null)
  const [bestLoading, setBestLoading] = useState(false)

  const csrf = () => document.querySelector('meta[name="csrf-token"]')?.content || ''

  const handleSuggestedClick = (q) => setQuestion(q)

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (!question.trim() || loading) return

    const id = `t-${Date.now()}`
    const baseTurn = { id, question: question.trim(), agentic: agentic_enabled }
    setTurns((prev) => [...prev, baseTurn])
    setLoading(true)
    setQuestion('')

    try {
      const res = await fetch('/ai/ask', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrf(),
          Accept: 'application/json',
        },
        body: JSON.stringify({
          question: baseTurn.question,
          mode: mode === 'itr' ? 'itr' : undefined,
          year: mode === 'itr' ? itrYear : undefined,
        }),
        credentials: 'same-origin',
      })
      const data = await res.json()

      setTurns((prev) =>
        prev.map((t) =>
          t.id === id
            ? {
                ...t,
                error: !res.ok ? data.error || 'Something went wrong.' : undefined,
                answer: data.answer,
                tool_trail: data.tool_trail || [],
                proposals: data.proposals || [],
                proposalStatus: {},
                provider: data.provider,
                model: data.model,
                agentic: !!data.agentic,
                steps: data.steps || 1,
              }
            : t,
        ),
      )
    } catch (err) {
      setTurns((prev) =>
        prev.map((t) => (t.id === id ? { ...t, error: 'Failed to reach the assistant.' } : t)),
      )
    } finally {
      setLoading(false)
    }
  }

  const updateProposalStatus = (turnId, index, status) => {
    setTurns((prev) =>
      prev.map((t) => {
        if (t.id !== turnId) return t
        return { ...t, proposalStatus: { ...(t.proposalStatus || {}), [index]: status } }
      }),
    )
  }

  const handleApplyProposal = async (turnId, index) => {
    const turn = turns.find((t) => t.id === turnId)
    const proposal = turn?.proposals?.[index]
    if (!proposal) return

    updateProposalStatus(turnId, index, 'applying')
    try {
      const res = await fetch('/ai/proposals/apply', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrf(),
          Accept: 'application/json',
        },
        body: JSON.stringify({ token: proposal.token }),
        credentials: 'same-origin',
      })
      const data = await res.json()
      if (!res.ok) {
        updateProposalStatus(turnId, index, { error: data.error || 'Apply failed.' })
        return
      }
      updateProposalStatus(turnId, index, 'applied')
    } catch (err) {
      updateProposalStatus(turnId, index, { error: 'Network error during apply.' })
    }
  }

  const handleRejectProposal = (turnId, index) => {
    updateProposalStatus(turnId, index, 'rejected')
  }

  const handleBestCard = async (e) => {
    e.preventDefault()
    setBestLoading(true)
    setBestResult(null)
    try {
      const res = await fetch('/credit_cards/best_for', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrf(),
          Accept: 'application/json',
        },
        body: JSON.stringify({
          category: bestCategory || undefined,
          merchant: bestMerchant || undefined,
          amount: bestAmount || undefined,
        }),
        credentials: 'same-origin',
      })
      const data = await res.json()
      setBestResult(data)
    } catch {
      setBestResult({ message: 'Could not get recommendation.' })
    } finally {
      setBestLoading(false)
    }
  }

  return (
    <DashboardLayout title="AI Assistant">
      <div className="max-w-3xl mx-auto space-y-8">
        <div>
          <h2 className="text-xl font-semibold text-slate-100 mb-2">Savvy — AI Assistant</h2>
          <div className="flex flex-wrap items-center gap-2 mb-3">
            <button
              type="button"
              onClick={() => setMode('spending')}
              className={`px-3 py-1.5 rounded-lg text-sm font-medium ${
                mode === 'spending'
                  ? 'bg-gradient-to-r from-violet-600 to-fuchsia-600 text-white'
                  : 'bg-white/10 text-slate-300'
              }`}
            >
              Spending
            </button>
            <button
              type="button"
              onClick={() => setMode('itr')}
              className={`px-3 py-1.5 rounded-lg text-sm font-medium ${
                mode === 'itr'
                  ? 'bg-gradient-to-r from-violet-600 to-fuchsia-600 text-white'
                  : 'bg-white/10 text-slate-300'
              }`}
            >
              ITR & tax
            </button>
            {mode === 'itr' && itr_years.length > 0 && (
              <select
                value={itrYear}
                onChange={(e) => setItrYear(Number(e.target.value))}
                className="px-2 py-1.5 rounded-lg border border-white/10 bg-white/5 text-sm text-slate-200"
              >
                {itr_years.map((y) => (
                  <option key={y} value={y}>
                    FY {y}
                  </option>
                ))}
              </select>
            )}
            <span className="ml-auto inline-flex items-center gap-1 text-xs text-slate-500">
              {agentic_enabled ? (
                <>
                  <BoltIcon className="h-3.5 w-3.5 text-violet-300" /> Agent mode · {ai_provider}
                </>
              ) : (
                <>Single-shot · {ai_provider}</>
              )}
            </span>
          </div>
          <p className="text-slate-400">
            {agentic_enabled
              ? 'Savvy uses tools to search your data step-by-step. It can propose changes (recategorise, budgets, rules) — you confirm before they apply.'
              : 'Savvy reads pre-built summaries of your statement data and answers questions. Enable agentic mode in Settings (and use Gemini or OpenAI) for tool-driven answers.'}
          </p>
          {credit_cards.length > 0 && (
            <p className="text-sm text-slate-500 mt-2">
              {credit_cards.length} card(s) in your profile — card-aware answers enabled.
            </p>
          )}
        </div>

        {/* Best card for purchase */}
        <div className="sl-card p-6">
          <div className="flex items-center gap-2 mb-4">
            <CreditCardIcon className="h-5 w-5 text-amber-400" />
            <h3 className="font-semibold text-slate-100">Which card should I use?</h3>
          </div>
          <form onSubmit={handleBestCard} className="space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <div>
                <label className="block text-xs font-medium text-slate-500 mb-1">Category</label>
                <select
                  value={bestCategory}
                  onChange={(e) => setBestCategory(e.target.value)}
                  className="sl-input"
                >
                  <option value="">Any / infer from merchant</option>
                  {categories.map((c) => (
                    <option key={c} value={c}>{c}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-slate-500 mb-1">Merchant (optional)</label>
                <input
                  type="text"
                  value={bestMerchant}
                  onChange={(e) => setBestMerchant(e.target.value)}
                  placeholder="e.g. Swiggy, Amazon"
                  className="sl-input"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-slate-500 mb-1">Amount (₹)</label>
                <input
                  type="number"
                  value={bestAmount}
                  onChange={(e) => setBestAmount(e.target.value)}
                  placeholder="3000"
                  className="sl-input"
                />
              </div>
            </div>
            <button
              type="submit"
              disabled={bestLoading || credit_cards.length === 0}
              className="sl-btn-primary px-4 py-2 text-sm"
            >
              {bestLoading ? 'Checking...' : 'Find best card'}
            </button>
          </form>

          {credit_cards.length === 0 && (
            <p className="text-sm text-amber-300 mt-3">Add credit cards first to get recommendations.</p>
          )}

          {bestResult?.best && (
            <div className="mt-4 p-4 rounded-lg sl-alert-success">
              <p className="text-sm font-medium">Best choice</p>
              <p className="text-lg font-bold mt-1">{bestResult.best.card_name}</p>
              <p className="text-sm">
                {bestResult.best.rate_label} — est. {formatCurrency(bestResult.best.reward)} rewards
                {bestResult.amount ? ` on ${formatCurrency(bestResult.amount)} spend` : ''}
              </p>
            </div>
          )}

          {bestResult?.message && !bestResult?.best && (
            <p className="mt-3 text-sm text-amber-300">{bestResult.message}</p>
          )}
        </div>

        {/* Suggested questions */}
        <div>
          {mode === 'itr' ? (
            <>
              <p className="text-sm font-medium text-slate-300 mb-3">ITR questions</p>
              <div className="flex flex-wrap gap-2 mb-2">
                {ITR_QUESTIONS.map((q) => (
                  <button
                    key={q}
                    type="button"
                    onClick={() => handleSuggestedClick(q)}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-violet-500/30 bg-violet-500/10 px-3 py-2 text-sm text-violet-200 transition hover:bg-violet-500/20"
                  >
                    <SparklesIcon className="h-4 w-4 shrink-0" />
                    {q}
                  </button>
                ))}
              </div>
            </>
          ) : (
            <>
              <p className="text-sm font-medium text-slate-300 mb-3">Spending questions</p>
              <div className="flex flex-wrap gap-2 mb-4">
                {EXPENSE_QUESTIONS.map((q) => (
                  <button
                    key={q}
                    type="button"
                    onClick={() => handleSuggestedClick(q)}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-slate-300 transition hover:border-violet-500/40 hover:bg-violet-500/10"
                  >
                    <SparklesIcon className="h-4 w-4 shrink-0" />
                    {q}
                  </button>
                ))}
              </div>

              <p className="text-sm font-medium text-slate-300 mb-3">Search transactions</p>
              <div className="flex flex-wrap gap-2 mb-4">
                {SEARCH_QUESTIONS.map((q) => (
                  <button
                    key={q}
                    type="button"
                    onClick={() => handleSuggestedClick(q)}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-white/20 bg-white/5 px-3 py-2 text-sm text-slate-300 transition hover:border-slate-400 hover:bg-white/10"
                  >
                    {q}
                  </button>
                ))}
              </div>

              <p className="text-sm font-medium text-slate-300 mb-3">Credit card & rewards</p>
              <div className="flex flex-wrap gap-2 mb-4">
                {CARD_QUESTIONS.map((q) => (
                  <button
                    key={q}
                    type="button"
                    onClick={() => handleSuggestedClick(q)}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-sm text-amber-200 transition hover:bg-amber-500/20"
                  >
                    <CreditCardIcon className="h-4 w-4 shrink-0" />
                    {q}
                  </button>
                ))}
              </div>

              {agentic_writes_enabled && (
                <>
                  <p className="text-sm font-medium text-slate-300 mb-3">
                    Agent actions (proposed — you confirm before they apply)
                  </p>
                  <div className="flex flex-wrap gap-2">
                    {AGENTIC_ACTION_QUESTIONS.map((q) => (
                      <button
                        key={q}
                        type="button"
                        onClick={() => handleSuggestedClick(q)}
                        className="inline-flex items-center gap-1.5 rounded-lg border border-fuchsia-500/30 bg-fuchsia-500/10 px-3 py-2 text-sm text-fuchsia-200 transition hover:bg-fuchsia-500/20"
                      >
                        <BoltIcon className="h-4 w-4 shrink-0" />
                        {q}
                      </button>
                    ))}
                  </div>
                </>
              )}
            </>
          )}
        </div>

        {turns.length > 0 && (
          <div className="space-y-6">
            {turns.map((turn) => (
              <ChatTurn
                key={turn.id}
                turn={turn}
                onApplyProposal={handleApplyProposal}
                onRejectProposal={handleRejectProposal}
              />
            ))}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label htmlFor="question" className="block text-sm font-medium text-slate-300 mb-2">
              Your question
            </label>
            <textarea
              id="question"
              rows={3}
              value={question}
              onChange={(e) => setQuestion(e.target.value)}
              placeholder={agentic_enabled
                ? 'e.g. Find my uncategorised Swiggy transactions and suggest a Food category for them.'
                : 'e.g. Which card should I use for a ₹5,000 Amazon purchase?'}
              className="sl-input"
              disabled={loading}
            />
          </div>
          <button
            type="submit"
            disabled={loading || !question.trim()}
            className="sl-btn-primary px-6 py-3 disabled:opacity-50"
          >
            {loading ? 'Thinking…' : 'Ask Savvy'}
          </button>
        </form>
      </div>
    </DashboardLayout>
  )
}
