import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'

import { useAuthStore } from '../auth'

function stubFetch(...responses: Response[]) {
  const fetchMock = vi.fn()
  for (const response of responses) fetchMock.mockResolvedValueOnce(response)
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

const user = { id: 1, email: 'demo@billing-engine.dev', name: 'Demo Operator' }

beforeEach(() => {
  setActivePinia(createPinia())
})

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('auth store', () => {
  it('is signed in when the cookie still holds a session, asking only once', async () => {
    const fetchMock = stubFetch(new Response(JSON.stringify({ user }), { status: 200 }))
    const auth = useAuthStore()

    await Promise.all([auth.load(), auth.load()])
    await auth.load()

    expect(auth.status).toBe('signed_in')
    expect(auth.user).toEqual(user)
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('is signed out on a 401', async () => {
    stubFetch(
      new Response(JSON.stringify({ error: { code: 'unauthenticated', message: 'Not signed in' } }), {
        status: 401,
      }),
    )
    const auth = useAuthStore()

    await auth.load()

    expect(auth.status).toBe('signed_out')
  })

  it('signs out locally even when the request fails', async () => {
    stubFetch(new Response(JSON.stringify({ user }), { status: 201 }))
    const auth = useAuthStore()
    await auth.signIn(user.email, 'secret')
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('offline')))

    await auth.signOut()

    expect(auth.status).toBe('signed_out')
    expect(auth.user).toBeNull()
  })
})
