import { describe, expect, it } from 'vitest'

import { ApiError } from '../client'
import { keyAfterFailure } from '../idempotency'

describe('keyAfterFailure', () => {
  it('starts a new attempt after the API answered with a 4xx', () => {
    const error = new ApiError(422, 'invalid_resume_date', 'Past date')
    expect(keyAfterFailure('key-1', error)).not.toBe('key-1')
  })

  it('keeps the key when the outcome is unknown, so a retry is deduplicated', () => {
    expect(keyAfterFailure('key-1', new ApiError(0, 'network_error', 'Offline'))).toBe('key-1')
    expect(keyAfterFailure('key-1', new ApiError(502, 'http_error', 'Bad gateway'))).toBe('key-1')
  })
})
