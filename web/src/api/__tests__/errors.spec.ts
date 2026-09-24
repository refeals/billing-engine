import { describe, expect, it } from 'vitest'

import { ApiError } from '../client'
import { fieldErrors, toApiError } from '../errors'

describe('fieldErrors', () => {
  it('maps validation details to one message per field', () => {
    const error = new ApiError(422, 'validation_failed', 'Validation failed', {
      name: ["can't be blank"],
      amount_cents: ['must be greater than 0', 'must be an integer'],
    })

    expect(fieldErrors(error)).toEqual({
      name: "can't be blank",
      amount_cents: 'must be greater than 0, must be an integer',
    })
  })

  it('ignores errors that are not validation failures', () => {
    expect(fieldErrors(new ApiError(422, 'card_expired', 'Expired', { card: ['x'] }))).toEqual({})
    expect(fieldErrors(null)).toEqual({})
  })
})

describe('toApiError', () => {
  it('keeps ApiErrors and wraps anything else', () => {
    const apiError = new ApiError(409, 'stale_object', 'Reload')
    expect(toApiError(apiError)).toBe(apiError)
    expect(toApiError(new Error('boom'))).toMatchObject({ status: 0, code: 'unknown_error' })
  })
})
