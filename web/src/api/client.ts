const baseUrl = import.meta.env.VITE_API_URL ?? 'http://localhost:3001/api/v1'

type HttpMethod = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'

interface RequestOptions {
  method?: HttpMethod
  body?: unknown
  headers?: Record<string, string>
}

interface ErrorBody {
  error: { code: string; message: string; details?: Record<string, unknown> }
}

export class ApiError extends Error {
  readonly status: number
  readonly code: string
  readonly details: Record<string, unknown>

  constructor(
    status: number,
    code: string,
    message: string,
    details: Record<string, unknown> = {},
  ) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
    this.details = details
  }

  // A 409 means the record changed since it was loaded (optimistic lock or a reused
  // idempotency key). The only safe reaction is to reload, so views check this flag.
  get isConflict(): boolean {
    return this.status === 409
  }
}

// Called when a request comes back 401 (the session expired or was signed out elsewhere),
// so any screen falls back to the login instead of showing a broken view. The session
// endpoints themselves are excluded: a 401 there is an expected answer, not an event.
let onUnauthenticated: (() => void) | null = null

export function setUnauthenticatedHandler(handler: (() => void) | null) {
  onUnauthenticated = handler
}

export async function apiRequest<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const hasBody = options.body !== undefined
  let response: Response

  try {
    response = await fetch(`${baseUrl}${path}`, {
      method: options.method ?? 'GET',
      headers: {
        Accept: 'application/json',
        ...(hasBody ? { 'Content-Type': 'application/json' } : {}),
        ...options.headers,
      },
      body: hasBody ? JSON.stringify(options.body) : undefined,
      // The session lives in an HttpOnly cookie set by the API's own domain.
      credentials: 'include',
    })
  } catch {
    throw new ApiError(0, 'network_error', 'Could not reach the API. Is the Rails server running?')
  }

  const payload = await parseJson(response)
  if (response.ok) return payload as T
  if (response.status === 401 && path !== '/session') onUnauthenticated?.()

  if (isErrorBody(payload)) {
    const { code, message, details } = payload.error
    throw new ApiError(response.status, code, message, details)
  }
  throw new ApiError(response.status, 'http_error', `Request failed with status ${response.status}`)
}

async function parseJson(response: Response): Promise<unknown> {
  const text = await response.text()
  if (text === '') return null

  try {
    return JSON.parse(text)
  } catch {
    return null
  }
}

function isErrorBody(payload: unknown): payload is ErrorBody {
  if (typeof payload !== 'object' || payload === null || !('error' in payload)) return false

  const { error } = payload as { error: unknown }
  return typeof error === 'object' && error !== null && 'code' in error && 'message' in error
}
