import { Link } from '@inertiajs/react'

export default function AuthLayout({ children }) {
  return (
    <div className="relative min-h-screen flex flex-col items-center justify-center bg-slate-950 text-slate-100 overflow-hidden">
      <div className="pointer-events-none fixed inset-0">
        <div className="absolute -top-40 -right-32 h-[420px] w-[420px] rounded-full bg-violet-600/20 blur-[100px]" />
        <div className="absolute bottom-0 -left-32 h-[360px] w-[360px] rounded-full bg-fuchsia-600/15 blur-[80px]" />
      </div>

      <div className="absolute top-6 left-6 z-10">
        <Link href="/" className="flex items-center gap-2.5">
          <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-violet-500 to-fuchsia-600 text-white font-bold shadow-lg shadow-violet-600/30">
            S
          </span>
          <span className="text-lg font-semibold text-white tracking-tight">SpendLens</span>
        </Link>
      </div>

      <div className="relative w-full max-w-md px-6 py-24">{children}</div>
    </div>
  )
}
