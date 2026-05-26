import { Head, Link } from '@inertiajs/react'
import {
  SparklesIcon,
  DocumentTextIcon,
  ChatBubbleLeftRightIcon,
  TagIcon,
  BriefcaseIcon,
  ScaleIcon,
  ChartBarIcon,
  ShieldCheckIcon,
  ArrowRightIcon,
  BanknotesIcon,
  WalletIcon,
  DocumentArrowUpIcon,
  BoltIcon,
  CheckCircleIcon,
  CursorArrowRaysIcon,
} from '@heroicons/react/24/outline'

const aiFeatures = [
  {
    icon: DocumentArrowUpIcon,
    title: 'Smart statement reading',
    description:
      'Upload your bank PDF or CSV. SpendLens reads the file and pulls out transactions — even when layouts are messy — so you don’t type them in by hand.',
    accent: 'from-violet-500 to-purple-600',
  },
  {
    icon: TagIcon,
    title: 'Automatic categories',
    description:
      'Swiggy, salary, rent, mutual fund SIPs — transactions get sensible labels. The app learns from your corrections and can suggest new categories when needed.',
    accent: 'from-blue-500 to-cyan-500',
  },
  {
    icon: ChatBubbleLeftRightIcon,
    title: 'Savvy — your AI money coach',
    description:
      'Ask in plain English: “Where did I overspend last month?”, “Best card for groceries?”, “What’s missing for my ITR?” Savvy searches your real data step-by-step to answer.',
    accent: 'from-amber-500 to-orange-500',
  },
  {
    icon: BoltIcon,
    title: 'Smart agent that gets things done',
    description:
      'Savvy doesn’t just chat. It can find unsorted transactions, suggest budgets, and propose category rules. You always click Apply before anything changes — no surprises.',
    accent: 'from-fuchsia-500 to-pink-600',
  },
  {
    icon: DocumentTextIcon,
    title: 'Tax document understanding',
    description:
      'Upload Form 16, AIS, or broker statements. AI extracts key numbers so you can review salary, TDS, interest, and gains in one place.',
    accent: 'from-emerald-500 to-teal-500',
  },
  {
    icon: ScaleIcon,
    title: 'ITR prep assistant',
    description:
      'See readiness for the financial year, compare old vs new tax regime, reconcile AIS with your bank data, and get filing guidance — without replacing your CA.',
    accent: 'from-rose-500 to-pink-500',
  },
  {
    icon: BriefcaseIcon,
    title: 'Investment spotter',
    description:
      'Detects Zerodha, CAMS, NPS, FD interest, and more from bank lines. Suggests what to add to your portfolio so investments aren’t invisible.',
    accent: 'from-indigo-500 to-blue-600',
  },
]

const alsoIncludes = [
  { icon: ChartBarIcon, title: 'Dashboards & insights', text: 'Monthly trends, category breakdowns, budgets.' },
  { icon: WalletIcon, title: 'Net worth', text: 'Holdings and accounts in one view.' },
  { icon: BanknotesIcon, title: 'Credit card rewards', text: 'Compare cards and find the best one per spend type.' },
]

function Nav() {
  return (
    <header className="fixed top-0 inset-x-0 z-50 border-b border-white/10 bg-slate-950/70 backdrop-blur-xl">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 h-16 flex items-center justify-between">
        <Link href="/" className="flex items-center gap-2.5">
          <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-violet-500 to-fuchsia-600 text-white font-bold shadow-lg shadow-violet-500/30">
            S
          </span>
          <span className="text-lg font-semibold text-white tracking-tight">SpendLens</span>
        </Link>
        <nav className="flex items-center gap-3 sm:gap-4">
          <a href="#ai" className="hidden sm:inline text-sm text-slate-300 hover:text-white transition">
            AI features
          </a>
          <a href="#agent" className="hidden sm:inline text-sm text-slate-300 hover:text-white transition">
            Agent mode
          </a>
          <a href="#how" className="hidden sm:inline text-sm text-slate-300 hover:text-white transition">
            How it works
          </a>
          <Link
            href="/users/sign_in"
            className="text-sm font-medium text-slate-200 hover:text-white transition px-3 py-2"
          >
            Sign in
          </Link>
          <Link
            href="/users/sign_up"
            className="text-sm font-semibold text-white bg-white/10 hover:bg-white/15 border border-white/20 px-4 py-2 rounded-full transition"
          >
            Get started
          </Link>
        </nav>
      </div>
    </header>
  )
}

export default function HomeIndex() {
  return (
    <>
      <Head>
        <title>SpendLens — AI personal finance & tax prep for India</title>
        <meta
          name="description"
          content="Upload bank statements and let Savvy, your AI money agent, sort spending, suggest budgets, and get you ITR-ready. You confirm every change."
        />
      </Head>
      <div className="min-h-screen bg-slate-950 text-slate-100 antialiased">
      <div className="pointer-events-none fixed inset-0 overflow-hidden">
        <div className="absolute -top-40 -right-32 w-[520px] h-[520px] rounded-full bg-violet-600/25 blur-[100px]" />
        <div className="absolute top-1/3 -left-40 w-[480px] h-[480px] rounded-full bg-cyan-500/15 blur-[100px]" />
        <div className="absolute bottom-0 right-1/4 w-[400px] h-[400px] rounded-full bg-fuchsia-600/10 blur-[80px]" />
        <div
          className="absolute inset-0 opacity-[0.03]"
          style={{
            backgroundImage: `linear-gradient(rgba(255,255,255,.08) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,.08) 1px, transparent 1px)`,
            backgroundSize: '64px 64px',
          }}
        />
      </div>

      <Nav />

      <main className="relative pt-16">
        {/* Hero */}
        <section className="max-w-6xl mx-auto px-4 sm:px-6 pt-16 sm:pt-24 pb-20 sm:pb-28">
          <div className="inline-flex items-center gap-2 rounded-full border border-violet-400/30 bg-violet-500/10 px-4 py-1.5 text-sm text-violet-200 mb-8">
            <SparklesIcon className="h-4 w-4 text-violet-300" />
            <span>AI-powered personal finance for India</span>
          </div>

          <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold tracking-tight text-white max-w-4xl leading-[1.1]">
            See your money clearly.{' '}
            <span className="bg-gradient-to-r from-violet-300 via-fuchsia-200 to-cyan-300 bg-clip-text text-transparent">
              Let AI do the heavy lifting.
            </span>
          </h1>

          <p className="mt-6 text-lg sm:text-xl text-slate-400 max-w-2xl leading-relaxed">
            SpendLens turns bank statements into organised spending, investments, and tax-ready summaries.
            Talk to <span className="text-violet-300 font-medium">Savvy</span>, your AI money coach — it can search your data, spot patterns,
            and even tidy things up for you. You confirm every change.
          </p>

          <div className="mt-10 flex flex-col sm:flex-row gap-4">
            <Link
              href="/users/sign_up"
              className="inline-flex items-center justify-center gap-2 px-8 py-4 rounded-2xl bg-gradient-to-r from-violet-600 to-fuchsia-600 text-white font-semibold text-lg shadow-xl shadow-violet-600/25 hover:from-violet-500 hover:to-fuchsia-500 transition"
            >
              Create free account
              <ArrowRightIcon className="h-5 w-5" />
            </Link>
            <Link
              href="/users/sign_in"
              className="inline-flex items-center justify-center px-8 py-4 rounded-2xl border border-slate-600 text-slate-200 font-semibold text-lg hover:bg-white/5 transition"
            >
              I already have an account
            </Link>
          </div>

          <div className="mt-12 flex flex-wrap gap-6 text-sm text-slate-500">
            <span className="flex items-center gap-2">
              <ShieldCheckIcon className="h-5 w-5 text-emerald-400" />
              You confirm before anything changes
            </span>
            <span className="flex items-center gap-2">
              <DocumentTextIcon className="h-5 w-5 text-violet-400" />
              Indian financial year (Apr–Mar)
            </span>
            <span className="flex items-center gap-2">
              <SparklesIcon className="h-5 w-5 text-amber-400" />
              Private local AI or fast cloud AI — your choice
            </span>
          </div>
        </section>

        {/* AI features */}
        <section id="ai" className="border-t border-white/5 bg-slate-900/50 py-20 sm:py-28">
          <div className="max-w-6xl mx-auto px-4 sm:px-6">
            <div className="text-center max-w-2xl mx-auto mb-14">
              <p className="text-violet-400 font-semibold text-sm uppercase tracking-wider mb-3">Artificial intelligence</p>
              <h2 className="text-3xl sm:text-4xl font-bold text-white">
                Seven ways AI helps you stay on top of money
              </h2>
              <p className="mt-4 text-slate-400 text-lg">
                No finance degree required. Upload once, review what the app found, and let the agent help you tidy up.
              </p>
            </div>

            <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-6">
              {aiFeatures.map((feature) => (
                <article
                  key={feature.title}
                  className="group relative rounded-2xl border border-white/10 bg-slate-950/80 p-6 hover:border-white/20 hover:bg-slate-900/80 transition duration-300"
                >
                  <div
                    className={`inline-flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-br ${feature.accent} shadow-lg mb-5`}
                  >
                    <feature.icon className="h-6 w-6 text-white" />
                  </div>
                  <h3 className="text-lg font-semibold text-white mb-2">{feature.title}</h3>
                  <p className="text-slate-400 text-sm leading-relaxed">{feature.description}</p>
                </article>
              ))}
            </div>

            <div className="mt-12 rounded-2xl border border-amber-500/20 bg-amber-500/5 p-6 sm:p-8 flex flex-col sm:flex-row gap-4 sm:items-center sm:justify-between">
              <div>
                <p className="font-semibold text-amber-100 flex items-center gap-2">
                  <SparklesIcon className="h-5 w-5" />
                  Meet Savvy
                </p>
                <p className="mt-2 text-slate-400 text-sm sm:text-base max-w-xl">
                  Savvy is SpendLens’s AI assistant. Switch to “ITR mode” during tax season for checklist gaps,
                  regime hints, and reconciliation tips — always as guidance, not legal advice.
                </p>
              </div>
              <Link
                href="/users/sign_up"
                className="shrink-0 inline-flex items-center justify-center px-6 py-3 rounded-xl bg-amber-500/20 text-amber-100 font-medium border border-amber-500/30 hover:bg-amber-500/30 transition"
              >
                Try Savvy after sign-up
              </Link>
            </div>
          </div>
        </section>

        {/* Agent mode highlight */}
        <section id="agent" className="py-20 sm:py-24">
          <div className="max-w-6xl mx-auto px-4 sm:px-6">
            <div className="grid lg:grid-cols-2 gap-12 lg:gap-16 items-center">
              <div>
                <div className="inline-flex items-center gap-2 rounded-full border border-fuchsia-400/30 bg-fuchsia-500/10 px-3 py-1 text-xs font-medium text-fuchsia-200 mb-5">
                  <BoltIcon className="h-3.5 w-3.5" /> New — agent mode
                </div>
                <h2 className="text-3xl sm:text-4xl font-bold text-white tracking-tight">
                  An assistant that <span className="bg-gradient-to-r from-fuchsia-300 to-violet-300 bg-clip-text text-transparent">actually does things</span>
                </h2>
                <p className="mt-5 text-slate-400 text-lg leading-relaxed">
                  Older AI assistants just answer questions. Savvy can also <em>act</em> — search your transactions,
                  group spending, draft a budget, suggest a smart rule for repeat merchants. Everything it suggests
                  shows up as a clear card. <span className="text-white font-medium">Nothing happens until you click Apply.</span>
                </p>

                <ul className="mt-8 space-y-4">
                  {[
                    {
                      title: 'Watch it think',
                      text: 'See the steps Savvy took — which data it searched and what it found — before it answers.',
                    },
                    {
                      title: 'Propose, never auto-apply',
                      text: 'Recategorise transactions, create budgets, or add a category rule only after you say yes.',
                    },
                    {
                      title: 'Asks better questions back',
                      text: 'If something is missing — like a Form 16 or AIS — Savvy says so instead of guessing.',
                    },
                  ].map((point) => (
                    <li key={point.title} className="flex gap-3">
                      <CheckCircleIcon className="h-6 w-6 text-emerald-400 shrink-0 mt-0.5" />
                      <div>
                        <p className="font-semibold text-white">{point.title}</p>
                        <p className="text-slate-400 text-sm mt-0.5">{point.text}</p>
                      </div>
                    </li>
                  ))}
                </ul>

                <div className="mt-8">
                  <Link
                    href="/users/sign_up"
                    className="inline-flex items-center gap-2 px-6 py-3 rounded-xl bg-gradient-to-r from-fuchsia-600 to-violet-600 text-white font-semibold shadow-lg shadow-fuchsia-600/20 hover:from-fuchsia-500 hover:to-violet-500 transition"
                  >
                    Try the agent
                    <ArrowRightIcon className="h-4 w-4" />
                  </Link>
                </div>
              </div>

              {/* Mock chat */}
              <div className="relative">
                <div className="absolute -inset-4 bg-gradient-to-tr from-fuchsia-500/20 via-violet-500/10 to-transparent blur-2xl rounded-3xl" />
                <div className="relative rounded-2xl border border-white/10 bg-slate-900/80 backdrop-blur p-5 shadow-2xl shadow-violet-900/40">
                  <div className="flex items-center gap-2 mb-4">
                    <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-gradient-to-br from-violet-500 to-fuchsia-600 text-white text-xs font-bold">
                      S
                    </span>
                    <span className="text-sm font-medium text-white">Savvy</span>
                    <span className="ml-auto text-[10px] text-slate-500 inline-flex items-center gap-1">
                      <BoltIcon className="h-3 w-3 text-violet-300" /> Agent mode
                    </span>
                  </div>

                  <div className="space-y-3 text-sm">
                    <div className="flex justify-end">
                      <p className="max-w-[85%] rounded-xl rounded-tr-sm bg-slate-700/60 text-slate-100 px-3 py-2">
                        Find my unsorted Swiggy spends and put them in Food &amp; Dining.
                      </p>
                    </div>

                    <div className="rounded-xl border border-white/5 bg-white/5 px-3 py-2 text-xs text-slate-400">
                      <p className="text-violet-300 font-medium">searched · 12 transactions</p>
                      <p className="text-violet-300 font-medium mt-1">checked · Food &amp; Dining category</p>
                    </div>

                    <div className="rounded-xl rounded-tl-sm bg-slate-800/60 text-slate-200 px-3 py-2">
                      Found 12 Swiggy charges totalling ₹4,820. They all look like food orders.
                    </div>

                    <div className="rounded-xl border border-violet-500/40 bg-violet-500/10 p-3">
                      <p className="text-[10px] uppercase tracking-wider text-violet-300 font-semibold">Proposed change</p>
                      <p className="text-white font-medium mt-1">Recategorise 12 transactions → Food &amp; Dining</p>
                      <p className="text-xs text-slate-400 mt-0.5">Reason: all merchant lines start with “Swiggy”.</p>
                      <div className="mt-3 flex justify-end gap-2">
                        <button
                          type="button"
                          className="px-2.5 py-1 text-xs rounded-md border border-white/10 text-slate-300 cursor-default"
                        >
                          Reject
                        </button>
                        <button
                          type="button"
                          className="px-2.5 py-1 text-xs rounded-md bg-gradient-to-r from-violet-600 to-fuchsia-600 text-white cursor-default inline-flex items-center gap-1"
                        >
                          <CursorArrowRaysIcon className="h-3 w-3" /> Apply
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* How it works */}
        <section id="how" className="border-t border-white/5 bg-slate-900/40 py-20 sm:py-28">
          <div className="max-w-6xl mx-auto px-4 sm:px-6">
            <h2 className="text-3xl sm:text-4xl font-bold text-white text-center mb-14">How it works</h2>
            <ol className="grid md:grid-cols-4 gap-8 md:gap-6">
              {[
                {
                  step: '1',
                  title: 'Upload',
                  text: 'Add your bank or card statement — PDF or CSV from any major Indian bank.',
                },
                {
                  step: '2',
                  title: 'Review',
                  text: 'AI and smart rules categorise spending, flag investments, and surface tax-relevant amounts.',
                },
                {
                  step: '3',
                  title: 'Ask Savvy',
                  text: 'Chat in plain English. Savvy searches your real data and explains what it found, step by step.',
                },
                {
                  step: '4',
                  title: 'Confirm changes',
                  text: 'Savvy proposes tidy-ups — recategorise, budgets, rules. You see them as cards and click Apply.',
                },
              ].map((item) => (
                <li key={item.step} className="relative text-center md:text-left">
                  <span className="inline-flex h-10 w-10 items-center justify-center rounded-full bg-violet-600/30 text-violet-200 font-bold border border-violet-500/40 mb-4">
                    {item.step}
                  </span>
                  <h3 className="text-xl font-semibold text-white mb-2">{item.title}</h3>
                  <p className="text-slate-400 leading-relaxed">{item.text}</p>
                </li>
              ))}
            </ol>
          </div>
        </section>

        {/* Also includes */}
        <section className="border-t border-white/5 py-16 sm:py-20">
          <div className="max-w-6xl mx-auto px-4 sm:px-6">
            <h2 className="text-2xl font-bold text-white text-center mb-10">Everything else in one app</h2>
            <div className="grid sm:grid-cols-3 gap-6">
              {alsoIncludes.map((item) => (
                <div
                  key={item.title}
                  className="rounded-xl border border-white/10 bg-white/5 p-5 text-center sm:text-left"
                >
                  <item.icon className="h-8 w-8 text-violet-400 mx-auto sm:mx-0 mb-3" />
                  <h3 className="font-semibold text-white">{item.title}</h3>
                  <p className="text-sm text-slate-400 mt-1">{item.text}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* CTA */}
        <section className="py-20 sm:py-24">
          <div className="max-w-4xl mx-auto px-4 sm:px-6 text-center">
            <div className="rounded-3xl bg-gradient-to-br from-violet-600/40 via-fuchsia-600/30 to-slate-900 border border-white/10 p-10 sm:p-14">
              <h2 className="text-2xl sm:text-3xl font-bold text-white">Ready to understand your finances?</h2>
              <p className="mt-4 text-slate-300 max-w-lg mx-auto">
                Sign up in minutes. Connect your statements, turn on AI in Settings, and start with your dashboard.
              </p>
              <Link
                href="/users/sign_up"
                className="mt-8 inline-flex items-center gap-2 px-8 py-4 rounded-2xl bg-white text-slate-900 font-semibold text-lg hover:bg-slate-100 transition shadow-xl"
              >
                Get started free
                <ArrowRightIcon className="h-5 w-5" />
              </Link>
            </div>
          </div>
        </section>
      </main>

      <footer className="border-t border-white/10 py-10">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 text-center text-sm text-slate-500 space-y-2">
          <p className="font-medium text-slate-400">SpendLens</p>
          <p>
            Assistive tool for personal finance and tax preparation. Not a substitute for a chartered accountant or
            official tax filing on incometax.gov.in.
          </p>
          <p className="pt-4">
            <Link href="/users/sign_in" className="text-violet-400 hover:text-violet-300">
              Sign in
            </Link>
            <span className="mx-2">·</span>
            <Link href="/users/sign_up" className="text-violet-400 hover:text-violet-300">
              Create account
            </Link>
          </p>
        </div>
      </footer>
      </div>
    </>
  )
}
