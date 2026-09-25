import { apiRequest } from './client'

export interface SessionUser {
  id: number
  email: string
  name: string
}

export { DEMO_CREDENTIALS } from './demoCredentials'

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
