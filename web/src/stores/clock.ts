import { ref } from 'vue'
import { defineStore } from 'pinia'

import type { ApiError } from '@/api/client'
import { advanceClock, fetchClock, resetClock, type AdvanceResult } from '@/api/clock'
import { toApiError } from '@/api/errors'

export const useClockStore = defineStore('clock', () => {
  const now = ref<string | null>(null)
  const pending = ref(false)
  const error = ref<ApiError | null>(null)
  const lastAdvance = ref<AdvanceResult | null>(null)
  // Bumped whenever simulated time changes. Views watch it (via useClockRefresh) because
  // moving time can renew, charge or cancel anything they are showing.
  const revision = ref(0)

  async function track<T>(action: () => Promise<T>): Promise<T | null> {
    pending.value = true
    error.value = null
    try {
      return await action()
    } catch (caught) {
      error.value = toApiError(caught)
      return null
    } finally {
      pending.value = false
    }
  }

  async function load() {
    const result = await track(fetchClock)
    if (result) now.value = result.now
  }

  async function advance(days: number) {
    const result = await track(() => advanceClock(days))
    if (!result) return

    now.value = result.now
    lastAdvance.value = result
    revision.value += 1
  }

  async function reset() {
    const result = await track(resetClock)
    if (!result) return

    now.value = result.now
    lastAdvance.value = null
    revision.value += 1
  }

  // Something other than the clock widget moved time (a scenario, a demo reset).
  async function timeMoved() {
    await load()
    lastAdvance.value = null
    revision.value += 1
  }

  return { now, pending, error, lastAdvance, revision, load, advance, reset, timeMoved }
})
