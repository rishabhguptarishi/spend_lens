import { Link, usePage } from '@inertiajs/react'
import {
  HomeIcon,
  BanknotesIcon,
  CreditCardIcon,
  DocumentArrowUpIcon,
  ChartBarIcon,
  ChartPieIcon,
  DocumentTextIcon,
  Cog6ToothIcon,
  AdjustmentsHorizontalIcon,
  ArrowRightOnRectangleIcon,
  Bars3Icon,
  XMarkIcon,
  CurrencyDollarIcon,
  SparklesIcon,
  Squares2X2Icon,
  BriefcaseIcon,
  WalletIcon,
} from '@heroicons/react/24/outline'
import { useState } from 'react'

const navItems = [
  { icon: HomeIcon, name: 'Dashboard', href: '/dashboard' },
  { icon: DocumentArrowUpIcon, name: 'Upload', href: '/upload' },
  { icon: BanknotesIcon, name: 'Bank Accounts', href: '/bank_accounts' },
  { icon: CreditCardIcon, name: 'Credit Cards', href: '/credit_cards' },
  { icon: ChartBarIcon, name: 'Transactions', href: '/transactions' },
  { icon: ChartPieIcon, name: 'Insights', href: '/insights' },
  { icon: BriefcaseIcon, name: 'Investments', href: '/investments' },
  { icon: DocumentTextIcon, name: 'ITR', href: '/itr' },
  { icon: WalletIcon, name: 'Net worth', href: '/net_worth' },
  { icon: CurrencyDollarIcon, name: 'Budgets', href: '/budgets' },
  { icon: Squares2X2Icon, name: 'Card Comparison', href: '/cards' },
  { icon: Cog6ToothIcon, name: 'Categories', href: '/categories' },
  { icon: AdjustmentsHorizontalIcon, name: 'Settings', href: '/settings' },
  { icon: SparklesIcon, name: 'AI Assistant', href: '/ai' },
]

function NavLink({ icon: Icon, name, href, onClick, active }) {
  return (
    <Link
      href={href}
      onClick={onClick}
      className={`flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition focus:outline-none focus:ring-2 focus:ring-violet-500/40 ${
        active
          ? 'bg-gradient-to-r from-violet-600/30 to-fuchsia-600/20 text-white border border-violet-500/30'
          : 'text-slate-400 hover:bg-white/5 hover:text-slate-100 border border-transparent'
      }`}
    >
      <Icon className={`h-5 w-5 shrink-0 ${active ? 'text-violet-300' : ''}`} />
      {name}
    </Link>
  )
}

function SidebarContent({ onNavigate, activePath }) {
  return (
    <>
      <div className="flex h-16 items-center gap-2.5 px-5 border-b border-white/10">
        <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-violet-500 to-fuchsia-600 text-white font-bold shadow-lg shadow-violet-600/30">
          S
        </span>
        <span className="text-lg font-semibold text-white tracking-tight">SpendLens</span>
      </div>
      <nav className="flex-1 space-y-0.5 overflow-y-auto px-3 py-4">
        {navItems.map((item) => (
          <NavLink
            key={item.href}
            {...item}
            onClick={onNavigate}
            active={activePath === item.href || (item.href !== '/dashboard' && activePath.startsWith(item.href))}
          />
        ))}
      </nav>
      <div className="border-t border-white/10 p-3">
        <Link
          href="/users/sign_out"
          method="delete"
          as="button"
          aria-label="Sign out"
          className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium text-slate-400 transition hover:bg-white/5 hover:text-slate-100"
        >
          <ArrowRightOnRectangleIcon className="h-5 w-5" />
          Sign Out
        </Link>
      </div>
    </>
  )
}

export default function DashboardLayout({ children, title = 'Dashboard' }) {
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const { url } = usePage()
  const activePath = url.split('?')[0]

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      {/* Ambient background */}
      <div className="pointer-events-none fixed inset-0 overflow-hidden">
        <div className="absolute -top-32 right-0 h-96 w-96 rounded-full bg-violet-600/10 blur-[100px]" />
        <div className="absolute bottom-0 left-1/4 h-80 w-80 rounded-full bg-fuchsia-600/8 blur-[80px]" />
      </div>

      {/* Desktop sidebar */}
      <aside className="fixed inset-y-0 left-0 z-50 hidden w-64 flex-col border-r border-white/10 bg-slate-950/90 backdrop-blur-xl lg:flex">
        <SidebarContent activePath={activePath} />
      </aside>

      {sidebarOpen && (
        <div className="fixed inset-0 z-40 bg-black/60 backdrop-blur-sm lg:hidden" onClick={() => setSidebarOpen(false)} />
      )}

      <aside
        className={`fixed inset-y-0 left-0 z-50 flex w-64 flex-col border-r border-white/10 bg-slate-950 backdrop-blur-xl transition-transform lg:hidden ${
          sidebarOpen ? 'translate-x-0' : '-translate-x-full'
        }`}
      >
        <div className="flex h-16 items-center justify-end px-4 border-b border-white/10 lg:hidden">
          <button
            type="button"
            onClick={() => setSidebarOpen(false)}
            className="rounded-lg p-2 text-slate-400 hover:bg-white/10 hover:text-white"
          >
            <XMarkIcon className="h-6 w-6" />
          </button>
        </div>
        <SidebarContent activePath={activePath} onNavigate={() => setSidebarOpen(false)} />
      </aside>

      <div className="relative lg:pl-64">
        <header className="sticky top-0 z-30 flex h-16 items-center gap-4 border-b border-white/10 bg-slate-950/80 px-4 backdrop-blur-xl sm:px-6 lg:px-8">
          <button
            type="button"
            onClick={() => setSidebarOpen(true)}
            className="rounded-lg p-2 text-slate-400 hover:bg-white/10 hover:text-white lg:hidden"
          >
            <Bars3Icon className="h-6 w-6" />
          </button>
          <div className="flex-1">
            <h1 className="text-lg font-semibold text-white">{title}</h1>
          </div>
          <Link href="/ai" className="hidden sm:inline-flex items-center gap-1.5 sl-btn-secondary py-2 text-xs">
            <SparklesIcon className="h-4 w-4 text-violet-400" />
            Ask Savvy
          </Link>
        </header>

        <main className="p-4 sm:p-6 lg:p-8">{children}</main>
      </div>
    </div>
  )
}
