import type { ApiError } from './client'

// One key per attempt: a double click or a retry after a network error reuses it, so the
// API applies the action once and replays the same response.
export function newIdempotencyKey(): string {
  return crypto.randomUUID()
}

export function idempotencyHeaders(key: string): Record<string, string> {
  return { 'Idempotency-Key': key }
}

// After a 4xx the attempt is over: the API answered and stored that answer. If the
// operator fixes the input and submits again, that is a new attempt and needs a new key,
// otherwise the API sees the old key with a different body and refuses it (409).
// Network errors and 5xx leave the outcome unknown, so the same key must be retried.
export function keyAfterFailure(key: string, error: ApiError): string {
  return error.status >= 400 && error.status < 500 ? newIdempotencyKey() : key
}
