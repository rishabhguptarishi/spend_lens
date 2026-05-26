import { useForm } from '@inertiajs/react'
import { Link } from '@inertiajs/react'
import AuthLayout from '../../Layouts/AuthLayout'

export default function Register({ errors: propErrors = {} }) {
  const { data, setData, post, processing, errors } = useForm({
    user: {
      email: '',
      password: '',
      password_confirmation: '',
    },
  })

  return (
    <AuthLayout>
      <h1 className="text-3xl font-bold text-white text-center mb-2">Create account</h1>
      <p className="text-slate-400 text-center mb-8">Sign up for SpendLens</p>

      {(errors?.email || errors?.password || propErrors?.email || propErrors?.password) && (
        <div className="mb-4 sl-alert-error text-sm">Please fix the errors below to continue.</div>
      )}

      <form
        onSubmit={(e) => {
          e.preventDefault()
          post('/users', { preserveScroll: true })
        }}
        className="space-y-4 sl-card p-8"
      >
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
          {(errors?.email || propErrors?.email) && (
            <p className="text-red-400 text-sm mt-1">{errors?.email || propErrors?.email}</p>
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
            autoComplete="new-password"
            className="sl-input"
            placeholder="Min 6 characters"
          />
          {(errors?.password || propErrors?.password) && (
            <p className="text-red-400 text-sm mt-1">{errors?.password || propErrors?.password}</p>
          )}
        </div>

        <div>
          <label htmlFor="password_confirmation" className="sl-label">
            Confirm password
          </label>
          <input
            id="password_confirmation"
            type="password"
            value={data.user?.password_confirmation || ''}
            onChange={(e) => setData('user', { ...data.user, password_confirmation: e.target.value })}
            autoComplete="new-password"
            className="sl-input"
          />
          {(errors?.password_confirmation || propErrors?.password_confirmation) && (
            <p className="text-red-400 text-sm mt-1">
              {errors?.password_confirmation || propErrors?.password_confirmation}
            </p>
          )}
        </div>

        <button type="submit" disabled={processing} className="w-full sl-btn-primary py-3">
          {processing ? 'Creating account...' : 'Sign up'}
        </button>
      </form>

      <p className="mt-6 text-center text-slate-400">
        Already have an account?{' '}
        <Link href="/users/sign_in" className="text-violet-400 font-medium hover:text-violet-300">
          Sign in
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
