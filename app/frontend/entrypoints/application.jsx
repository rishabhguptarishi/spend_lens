import { createInertiaApp } from '@inertiajs/react'
import { createRoot } from 'react-dom/client'
import '../index.css'

const appName = 'SpendLens'

createInertiaApp({
  title: (title) => (title ? `${title} - ${appName}` : appName),
  resolve: (name) => {
    const pages = import.meta.glob('../Pages/**/*.jsx')
    const page = pages[`../Pages/${name}.jsx`]
    if (!page) throw new Error(`Page not found: ${name}`)
    return page()
  },
  setup({ el, App, props }) {
    const root = createRoot(el)
    root.render(<App {...props} />)
  },
  progress: {
    color: '#2563eb',
    showSpinner: true,
  },
})
