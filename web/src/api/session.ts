import { apiRequest } from './client'

export interface SessionUser {
  id: number
  email: string
  name: string
}

// Public on purpose: the demo login shows them. Must match Demo::User in the API
// (api/app/services/demo/user.rb).
export const DEMO_CREDENTIALS = {
  email: 'demo@billing-engine.dev',
  password: 'demo-billing-2026',
} as const

export function fetchSession() {
  return apiRequest<{ user: SessionUser }>('/session')
}

export function signIn(email: string, password: string) {
  return apiRequest<{ user: SessionUser }>('/session', {
    method: 'POST',
    body: { email, password },
  })
}

export function signOut() {
  return apiRequest<null>('/session', { method: 'DELETE' })
}
