import { afterEach, describe, expect, it, vi } from 'vitest'

import { ApiError, apiRequest, setUnauthenticatedHandler } from '../client'

function stubFetch(status: number, body: string) {
  const fetchMock = vi.fn().mockResolvedValue(new Response(body || null, { status }))
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

async function captureError(promise: Promise<unknown>): Promise<ApiError> {
  try {
    await promise
  } catch (error) {
    if (error instanceof ApiError) return error
    throw error
  }
  throw new Error('expected the request to fail')
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('apiRequest', () => {
  it('returns the parsed JSON body on success', async () => {
    stubFetch(200, JSON.stringify({ now: '2026-10-01T12:00:00Z' }))

    await expect(apiRequest('/simulator/clock')).resolves.toEqual({ now: '2026-10-01T12:00:00Z' })
  })

  it('sends a JSON body with the matching content type', async () => {
    const fetchMock = stubFetch(200, '{}')

    await apiRequest('/simulator/clock/advance', { method: 'POST', body: { days: 3 } })

    const [url, init] = fetchMock.mock.calls[0]!
    expect(url).toMatch(/\/simulator\/clock\/advance$/)
    expect(init.method).toBe('POST')
    expect(init.body).toBe('{"days":3}')
    expect(init.headers['Content-Type']).toBe('application/json')
  })

  it('turns the standard error shape into an ApiError', async () => {
    stubFetch(
      422,
      JSON.stringify({
        error: { code: 'invalid_days', message: 'days must be...', details: { min: 1 } },
      }),
    )

    const error = await captureError(apiRequest('/simulator/clock/advance', { method: 'POST' }))

    expect(error.status).toBe(422)
    expect(error.code).toBe('invalid_days')
    expect(error.message).toBe('days must be...')
    expect(error.details).toEqual({ min: 1 })
    expect(error.isConflict).toBe(false)
  })

  it('flags 409 responses as conflicts', async () => {
    stubFetch(409, JSON.stringify({ error: { code: 'stale_object', message: 'Reload' } }))

    const error = await captureError(apiRequest('/subscriptions/1/cancel', { method: 'POST' }))

    expect(error.isConflict).toBe(true)
    expect(error.details).toEqual({})
  })

  it('falls back to a generic error when the body is not the standard shape', async () => {
    stubFetch(500, '<html>Internal Server Error</html>')

    const error = await captureError(apiRequest('/simulator/clock'))

    expect(error.status).toBe(500)
    expect(error.code).toBe('http_error')
  })

  it('reports network failures as network_error', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Failed to fetch')))

    const error = await captureError(apiRequest('/simulator/clock'))

    expect(error.status).toBe(0)
    expect(error.code).toBe('network_error')
  })
})

describe('session cookie and expiry', () => {
  afterEach(() => {
    setUnauthenticatedHandler(null)
  })

  it('sends the session cookie with every request', async () => {
    const fetchMock = stubFetch(200, '{}')

    await apiRequest('/plans')

    expect(fetchMock.mock.calls[0]![1].credentials).toBe('include')
  })

  it('reports a 401 so the app can go back to the login', async () => {
    const handler = vi.fn()
    setUnauthenticatedHandler(handler)
    stubFetch(401, JSON.stringify({ error: { code: 'unauthenticated', message: 'Sign in' } }))

    await captureError(apiRequest('/plans'))

    expect(handler).toHaveBeenCalledOnce()
  })

  it("doesn't treat the session endpoint's own 401 as an expiry", async () => {
    const handler = vi.fn()
    setUnauthenticatedHandler(handler)
    stubFetch(401, JSON.stringify({ error: { code: 'invalid_credentials', message: 'Wrong' } }))

    await captureError(apiRequest('/session', { method: 'POST', body: {} }))

    expect(handler).not.toHaveBeenCalled()
  })
})
