import { afterEach, describe, expect, it, vi } from 'vitest'

import { isCheck, resetDemoData, runScenario } from '../scenarios'

function stubFetch() {
  const fetchMock = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }))
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('resetDemoData', () => {
  it('sends the explicit confirmation the API requires', async () => {
    const fetchMock = stubFetch()

    await resetDemoData()

    expect(fetchMock.mock.calls[0]![0]).toMatch(/\/simulator\/reset$/)
    expect(JSON.parse(fetchMock.mock.calls[0]![1].body)).toEqual({ confirm: 'reset' })
  })
})

describe('runScenario', () => {
  it('escapes the scenario key in the path', async () => {
    const fetchMock = stubFetch()

    await runScenario('happy path')

    expect(fetchMock.mock.calls[0]![0]).toMatch(/\/simulator\/scenarios\/happy%20path\/run$/)
  })
})

describe('isCheck', () => {
  it('recognizes the steps a scenario asserts', () => {
    expect(isCheck({ step: '✓ the payment was recorded once', at: '2026-03-16T09:00:00Z' })).toBe(true)
    expect(isCheck({ step: 'Clock advanced 3 days', at: '2026-03-16T09:00:00Z' })).toBe(false)
  })
})
