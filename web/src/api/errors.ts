import { ApiError } from './client'

export function toApiError(caught: unknown): ApiError {
  return caught instanceof ApiError ? caught : new ApiError(0, 'unknown_error', String(caught))
}

// Rails validation errors (`details: { field: ["can't be blank"] }`) keyed by field, ready
// to show under each input.
export function fieldErrors(error: ApiError | null): Record<string, string> {
  if (!error || error.code !== 'validation_failed') return {}

  const errors: Record<string, string> = {}
  for (const [field, messages] of Object.entries(error.details)) {
    if (Array.isArray(messages) && messages.length > 0) errors[field] = messages.join(', ')
  }
  return errors
}
