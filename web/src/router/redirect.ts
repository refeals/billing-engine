// Where to go after signing in. Only internal paths are accepted: `?redirect=//evil.com`
// or a full URL would turn the login into an open redirect.
export function safeRedirect(value: unknown): string {
  if (typeof value !== 'string') return '/'
  if (!value.startsWith('/') || value.startsWith('//') || value.startsWith('/\\')) return '/'

  return value
}
