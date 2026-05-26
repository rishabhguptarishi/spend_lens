import { Link, useForm, usePage } from '@inertiajs/react'
import AuthLayout from '../../Layouts/AuthLayout'

export default function Login() {
  const { errors: pageErrors = {} } = usePage().props
  const { data, setData, post, processing, errors } = useForm({
    user: {
      email: '',
      password: '',
      remember_me: false,
    },
  })

  const authError = pageErrors?.base || errors?.base

  return (
    <AuthLayout>
      <h1 className="text-3xl font-bold text-white text-center mb-2">Welcome back</h1>
      <p className="text-slate-400 text-center mb-8">Sign in to SpendLens</p>

      <form
        onSubmit={(e) => {
          e.preventDefault()
          post('/users/sign_in', { preserveScroll: true, preserveState: false })
        }}
        className="space-y-4 sl-card p-8"
      >
        {authError && (
          <div className="sl-alert-error text-sm text-center" role="alert">
            {authError}
          </div>
        )}

        <div>
          <label htmlFor="email" className="sl-label">
            Email
          </label>
          <input
            id="email"
            type="email"
            value={data.user?.email || ''}
            onChange={(e) => setData('user', { ...data.user, email: e.target.value })}
            autoComplete="email"
            className="sl-input"
            placeholder="you@example.com"
          />
          {(errors?.email || pageErrors?.email) && (
            <p className="text-red-400 text-sm mt-1">{errors?.email || pageErrors?.email}</p>
          )}
        </div>

        <div>
          <label htmlFor="password" className="sl-label">
            Password
          </label>
          <input
            id="password"
            type="password"
            value={data.user?.password || ''}
            onChange={(e) => setData('user', { ...data.user, password: e.target.value })}
            autoComplete="current-password"
            className="sl-input"
          />
          {(errors?.password || pageErrors?.password) && (
            <p className="text-red-400 text-sm mt-1">{errors?.password || pageErrors?.password}</p>
          )}
        </div>

        <div className="flex items-center">
          <input
            id="remember_me"
            type="checkbox"
            checked={data.user?.remember_me || false}
            onChange={(e) => setData('user', { ...data.user, remember_me: e.target.checked })}
            className="sl-checkbox"
          />
          <label htmlFor="remember_me" className="ml-2 text-sm text-slate-400">
            Remember me
          </label>
        </div>

        <button type="submit" disabled={processing} className="w-full sl-btn-primary py-3">
          {processing ? 'Signing in...' : 'Sign in'}
        </button>
      </form>

      <p className="mt-6 text-center text-slate-400">
        Don&apos;t have an account?{' '}
        <Link href="/users/sign_up" className="text-violet-400 font-medium hover:text-violet-300">
          Sign up
        </Link>
      </p>
      <p className="mt-2 text-center">
        <Link href="/" className="text-slate-500 text-sm hover:text-slate-300">
          ← Back to home
        </Link>
      </p>
    </AuthLayout>
  )
}
