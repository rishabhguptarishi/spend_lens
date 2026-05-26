import { Link, useForm, usePage } from '@inertiajs/react'
import DashboardLayout from '../../Layouts/DashboardLayout'

function Toggle({ label, description, checked, onChange }) {
  return (
    <label className="flex items-start justify-between gap-4 py-3 border-b border-white/10 last:border-0 cursor-pointer">
      <div>
        <p className="font-medium text-slate-100">{label}</p>
        {description && <p className="text-sm text-slate-500 mt-0.5">{description}</p>}
      </div>
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        className="mt-1 sl-checkbox"
      />
    </label>
  )
}

function Section({ title, children }) {
  return (
    <section className="sl-card p-6 mb-6">
      <h2 className="text-lg font-semibold text-slate-100 mb-4">{title}</h2>
      {children}
    </section>
  )
}

export default function SettingsIndex({
  preferences = {},
  notifications = {},
  investment_rules = [],
  fy_years = [],
  current_fy,
  categories = [],
  asset_classes = [],
  kinds = [],
  account_kinds = [],
  tax_regimes = [],
  dashboard_views = [],
  system_detection_rules = [],
}) {
  const { ai_provider = 'ollama', ai_provider_label = 'AI' } = usePage().props
  const isOllama = ai_provider === 'ollama'
  const prefsForm = useForm({ preferences: { ...preferences } })
  const notifForm = useForm({ notifications: { ...notifications } })
  const ruleForm = useForm({
    investment_detection_rule: {
      pattern: '',
      asset_class: 'stock',
      kind: 'transfer_out',
      account_name: '',
      account_kind: 'broker',
    },
  })

  const p = prefsForm.data.preferences

  const setPref = (key, value) => {
    prefsForm.setData('preferences', { ...prefsForm.data.preferences, [key]: value })
  }

  return (
    <DashboardLayout title="Settings">
      <div className="max-w-3xl mx-auto">
        <div className="mb-8">
          <h1 className="text-2xl font-bold text-slate-900">Settings</h1>
          <p className="text-slate-400 mt-1">
            Control how SpendLens categorizes statements, detects investments, and prepares ITR data.
          </p>
        </div>

        <form
          onSubmit={(e) => {
            e.preventDefault()
            prefsForm.patch('/settings/preferences', { preserveScroll: true })
          }}
        >
          <Section title="General">
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">Default financial year</label>
                <select
                  value={p.default_fy_start || current_fy}
                  onChange={(e) => setPref('default_fy_start', parseInt(e.target.value, 10))}
                  className="w-full px-3 py-2 rounded-lg border border-white/10"
                >
                  {fy_years.map((y) => (
                    <option key={y} value={y}>
                      FY {y}–{(y + 1) % 100}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">Dashboard period</label>
                <select
                  value={p.dashboard_view || 'calendar_month'}
                  onChange={(e) => setPref('dashboard_view', e.target.value)}
                  className="w-full px-3 py-2 rounded-lg border border-white/10"
                >
                  {dashboard_views.map((v) => (
                    <option key={v} value={v}>
                      {v === 'financial_year' ? 'Full financial year (Apr–Mar)' : 'Calendar month'}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">Default category (when auto-categorize is limited)</label>
                <select
                  value={p.default_category_id || ''}
                  onChange={(e) => setPref('default_category_id', e.target.value || null)}
                  className="w-full px-3 py-2 rounded-lg border border-white/10"
                >
                  <option value="">Uncategorized</option>
                  {categories.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name}
                    </option>
                  ))}
                </select>
              </div>
            </div>
          </Section>

          <Section title="Bank statements">
            <Toggle
              label="Auto-categorize on upload"
              description="Use rules, AI, and keywords when parsing new statements."
              checked={p.auto_categorize_statements !== false}
              onChange={(v) => setPref('auto_categorize_statements', v)}
            />
          </Section>

          <Section title="Investments">
            <Toggle
              label="Auto-detect investments from bank transactions"
              description="Create suggestions after each statement is parsed."
              checked={p.auto_detect_investments !== false}
              onChange={(v) => setPref('auto_detect_investments', v)}
            />
          </Section>

          <Section title="ITR & tax">
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">Preferred tax regime</label>
                <select
                  value={p.preferred_tax_regime || 'auto'}
                  onChange={(e) => setPref('preferred_tax_regime', e.target.value)}
                  className="w-full px-3 py-2 rounded-lg border border-white/10"
                >
                  {tax_regimes.map((r) => (
                    <option key={r} value={r}>
                      {r === 'auto' ? 'Auto (compare both)' : r.charAt(0).toUpperCase() + r.slice(1) + ' regime'}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">
                  AIS reconciliation tolerance (%)
                </label>
                <input
                  type="number"
                  min="1"
                  max="50"
                  value={p.reconciliation_tolerance_pct ?? 10}
                  onChange={(e) => setPref('reconciliation_tolerance_pct', parseFloat(e.target.value))}
                  className="w-full px-3 py-2 rounded-lg border border-white/10"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">
                  Extra salary keywords (comma-separated)
                </label>
                <input
                  type="text"
                  value={p.salary_keywords || ''}
                  onChange={(e) => setPref('salary_keywords', e.target.value)}
                  placeholder="e.g. INFY, ACME PAYROLL"
                  className="w-full px-3 py-2 rounded-lg border border-white/10"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">
                  Extra business income keywords
                </label>
                <input
                  type="text"
                  value={p.business_keywords || ''}
                  onChange={(e) => setPref('business_keywords', e.target.value)}
                  placeholder="e.g. UPWORK, FIVERR"
                  className="w-full px-3 py-2 rounded-lg border border-white/10"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">
                  Extra interest keywords
                </label>
                <input
                  type="text"
                  value={p.interest_keywords || ''}
                  onChange={(e) => setPref('interest_keywords', e.target.value)}
                  placeholder="e.g. FD INT, SB INT"
                  className="w-full px-3 py-2 rounded-lg border border-white/10"
                />
              </div>
            </div>
          </Section>

          <Section title={`AI (${ai_provider_label})`}>
            <p className="text-xs text-slate-500 mb-3">
              Active provider is set by <code className="text-slate-400">AI_PROVIDER</code> in your environment. Change it there to switch between Ollama, Gemini, and OpenAI.
            </p>
            <Toggle
              label="Enable AI assistant"
              description="Savvy chat on /ai and statement intelligence."
              checked={p.ai_enabled !== false}
              onChange={(v) => setPref('ai_enabled', v)}
            />
            <Toggle
              label="AI categorization on upload"
              description={`Suggest categories via ${ai_provider_label} when parsing statements.`}
              checked={p.ai_categorize !== false}
              onChange={(v) => setPref('ai_categorize', v)}
            />
            <Toggle
              label="Allow AI to create new categories"
              description="If off, AI only maps to existing category names."
              checked={p.ai_create_categories !== false}
              onChange={(v) => setPref('ai_create_categories', v)}
            />
            <Toggle
              label="Agentic mode (multi-step tools)"
              description="Lets Savvy call tools to search/aggregate your data step-by-step. Needs AI_PROVIDER=gemini or openai."
              checked={p.ai_agentic_enabled !== false}
              onChange={(v) => setPref('ai_agentic_enabled', v)}
            />
            <Toggle
              label="Allow agent to propose changes"
              description="Savvy can suggest recategorising, budgets, or rules. You always confirm before they apply."
              checked={p.ai_agentic_writes !== false}
              onChange={(v) => setPref('ai_agentic_writes', v)}
            />
            <div className="mt-4 space-y-4">
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">AI context window (months)</label>
                <input
                  type="number"
                  min="1"
                  max="24"
                  value={p.ai_context_months ?? 6}
                  onChange={(e) => setPref('ai_context_months', parseInt(e.target.value, 10))}
                  className="w-full px-3 py-2 rounded-lg border border-white/10"
                />
              </div>
              {isOllama && (
                <>
                  <div>
                    <label className="block text-sm font-medium text-slate-300 mb-1">Ollama URL (optional)</label>
                    <input
                      type="text"
                      value={p.ollama_url || ''}
                      onChange={(e) => setPref('ollama_url', e.target.value)}
                      placeholder="http://localhost:11434"
                      className="w-full px-3 py-2 rounded-lg border border-white/10 font-mono text-sm"
                    />
                    <p className="text-xs text-slate-500 mt-1">Per-user override for the global <code>OLLAMA_URL</code>.</p>
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-slate-300 mb-1">Ollama model (optional)</label>
                    <input
                      type="text"
                      value={p.ollama_model || ''}
                      onChange={(e) => setPref('ollama_model', e.target.value)}
                      placeholder="llama3.2"
                      className="w-full px-3 py-2 rounded-lg border border-white/10 font-mono text-sm"
                    />
                    <p className="text-xs text-slate-500 mt-1">Per-user override for the global <code>OLLAMA_MODEL</code>.</p>
                  </div>
                </>
              )}
            </div>
          </Section>

          <div className="flex justify-end mb-8">
            <button
              type="submit"
              disabled={prefsForm.processing}
              className="px-6 py-2.5 sl-btn-primary disabled:opacity-50"
            >
              Save preferences
            </button>
          </div>
        </form>

        <form
          onSubmit={(e) => {
            e.preventDefault()
            notifForm.patch('/settings/notifications', { preserveScroll: true })
          }}
        >
          <Section title="Notifications">
            <Toggle
              label="Monthly digest email"
              checked={notifForm.data.notifications.monthly_digest !== false}
              onChange={(v) => notifForm.setData('notifications', { ...notifForm.data.notifications, monthly_digest: v })}
            />
            <Toggle
              label="Investment suggestions"
              description="Alerts when new bank transactions look like investments."
              checked={notifForm.data.notifications.investment_suggestions !== false}
              onChange={(v) =>
                notifForm.setData('notifications', { ...notifForm.data.notifications, investment_suggestions: v })
              }
            />
            <Toggle
              label="ITR season reminders"
              checked={notifForm.data.notifications.itr_season_reminders !== false}
              onChange={(v) =>
                notifForm.setData('notifications', { ...notifForm.data.notifications, itr_season_reminders: v })
              }
            />
            <Toggle
              label="Budget alerts"
              checked={notifForm.data.notifications.budget_alerts !== false}
              onChange={(v) =>
                notifForm.setData('notifications', { ...notifForm.data.notifications, budget_alerts: v })
              }
            />
            <div className="flex justify-end mt-4">
              <button
                type="submit"
                disabled={notifForm.processing}
                className="px-6 py-2.5 bg-slate-800 text-white font-medium rounded-xl hover:bg-slate-900 disabled:opacity-50"
              >
                Save notifications
              </button>
            </div>
          </Section>
        </form>

        <Section title="Custom investment detection rules">
          <p className="text-sm text-slate-400 mb-4">
            Your rules run before built-in patterns. Use regex-friendly text (e.g.{' '}
            <code className="bg-white/10 px-1 rounded">paytm money</code>).
          </p>

          {investment_rules.length > 0 && (
            <ul className="space-y-2 mb-6">
              {investment_rules.map((rule) => (
                <li
                  key={rule.id}
                  className="flex items-center justify-between gap-3 p-3 rounded-lg bg-white/5 border border-white/10"
                >
                  <div className="min-w-0">
                    <p className="font-mono text-sm text-slate-100 truncate">{rule.pattern}</p>
                    <p className="text-xs text-slate-500">
                      {rule.asset_class} · {rule.kind} → {rule.account_name}
                    </p>
                  </div>
                  <Link
                    href={`/settings/investment_rules/${rule.id}`}
                    method="delete"
                    as="button"
                    className="text-red-600 text-sm font-medium shrink-0"
                  >
                    Remove
                  </Link>
                </li>
              ))}
            </ul>
          )}

          <form
            onSubmit={(e) => {
              e.preventDefault()
              ruleForm.post('/settings/investment_rules', {
                preserveScroll: true,
                onSuccess: () => {
                  ruleForm.setData('investment_detection_rule', {
                    pattern: '',
                    asset_class: 'stock',
                    kind: 'transfer_out',
                    account_name: '',
                    account_kind: 'broker',
                  })
                },
              })
            }}
            className="space-y-3"
          >
            <input
              type="text"
              placeholder="Pattern (regex)"
              value={ruleForm.data.investment_detection_rule.pattern}
              onChange={(e) => ruleForm.setData('investment_detection_rule', { ...ruleForm.data.investment_detection_rule, pattern: e.target.value })}
              className="w-full px-3 py-2 rounded-lg border border-white/10 font-mono text-sm"
              required
            />
            <input
              type="text"
              placeholder="Account display name"
              value={ruleForm.data.investment_detection_rule.account_name}
              onChange={(e) =>
                ruleForm.setData('investment_detection_rule', {
                  ...ruleForm.data.investment_detection_rule,
                  account_name: e.target.value,
                })
              }
              className="w-full px-3 py-2 rounded-lg border border-white/10"
              required
            />
            <div className="grid grid-cols-2 gap-3">
              <select
                value={ruleForm.data.investment_detection_rule.asset_class}
                onChange={(e) =>
                  ruleForm.setData('investment_detection_rule', {
                    ...ruleForm.data.investment_detection_rule,
                    asset_class: e.target.value,
                  })
                }
                className="px-3 py-2 rounded-lg border border-white/10"
              >
                {asset_classes.map((a) => (
                  <option key={a} value={a}>
                    {a}
                  </option>
                ))}
              </select>
              <select
                value={ruleForm.data.investment_detection_rule.kind}
                onChange={(e) =>
                  ruleForm.setData('investment_detection_rule', {
                    ...ruleForm.data.investment_detection_rule,
                    kind: e.target.value,
                  })
                }
                className="px-3 py-2 rounded-lg border border-white/10"
              >
                {kinds.map((k) => (
                  <option key={k} value={k}>
                    {k}
                  </option>
                ))}
              </select>
            </div>
            <select
              value={ruleForm.data.investment_detection_rule.account_kind}
              onChange={(e) =>
                ruleForm.setData('investment_detection_rule', {
                  ...ruleForm.data.investment_detection_rule,
                  account_kind: e.target.value,
                })
              }
              className="w-full px-3 py-2 rounded-lg border border-white/10"
            >
              {account_kinds.map((k) => (
                <option key={k} value={k}>
                  {k}
                </option>
              ))}
            </select>
            <button
              type="submit"
              disabled={ruleForm.processing}
              className="w-full py-2.5 sl-btn-primary"
            >
              Add rule
            </button>
          </form>

          {system_detection_rules.length > 0 && (
            <details className="mt-6">
              <summary className="text-sm font-medium text-slate-400 cursor-pointer">
                Built-in detection patterns ({system_detection_rules.length})
              </summary>
              <ul className="mt-2 space-y-1 text-xs text-slate-500 font-mono">
                {system_detection_rules.map((r, i) => (
                  <li key={i}>
                    {r.pattern} → {r.asset_class}/{r.kind}
                  </li>
                ))}
              </ul>
            </details>
          )}
        </Section>
      </div>
    </DashboardLayout>
  )
}
