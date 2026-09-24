import { describe, expect, it } from 'vitest'

import { ApiError } from '@/api/client'
import { useAsyncData } from '../useAsyncData'

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (reason: unknown) => void
  const promise = new Promise<T>((res, rej) => {
    resolve = res
    reject = rej
  })
  return { promise, resolve, reject }
}

describe('useAsyncData', () => {
  it('stores the result and clears the loading flag', async () => {
    const { data, loading, reload } = useAsyncData(async () => 'plans')

    await reload()

    expect(data.value).toBe('plans')
    expect(loading.value).toBe(false)
  })

  it('ignores a slower response from an older request', async () => {
    const calls = [deferred<string>(), deferred<string>()]
    let call = 0
    const { data, reload } = useAsyncData(() => calls[call++]!.promise)

    const first = reload()
    const second = reload()
    calls[1]!.resolve('new filters')
    calls[0]!.resolve('old filters')
    await Promise.all([first, second])

    expect(data.value).toBe('new filters')
  })

  it('exposes failures as ApiError', async () => {
    const { error, reload } = useAsyncData(async () => {
      throw new ApiError(404, 'not_found', 'Missing')
    })

    await reload()

    expect(error.value?.code).toBe('not_found')
  })
})
