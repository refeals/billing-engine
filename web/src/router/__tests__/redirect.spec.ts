import { describe, expect, it } from 'vitest'

import { safeRedirect } from '../redirect'

describe('safeRedirect', () => {
  it('keeps internal paths, with their query', () => {
    expect(safeRedirect('/invoices?status=open')).toBe('/invoices?status=open')
  })

  it('refuses anything that would leave the app', () => {
    expect(safeRedirect('//evil.example')).toBe('/')
    expect(safeRedirect('/\\evil.example')).toBe('/')
    expect(safeRedirect('https://evil.example')).toBe('/')
    expect(safeRedirect(['/a', '/b'])).toBe('/')
    expect(safeRedirect(undefined)).toBe('/')
  })
})
