import { ref, shallowRef } from 'vue'

import type { ApiError } from '@/api/client'
import { toApiError } from '@/api/errors'

// Loads data for a view and tracks loading / error state. Only the latest call may write
// its result: a slow response for old filters must not replace a newer one.
export function useAsyncData<T>(loader: () => Promise<T>) {
  const data = shallowRef<T | null>(null)
  const error = ref<ApiError | null>(null)
  const loading = ref(false)
  let latestRequest = 0

  async function reload() {
    const request = ++latestRequest
    loading.value = true
    error.value = null

    try {
      const result = await loader()
      if (request === latestRequest) data.value = result
    } catch (caught) {
      if (request === latestRequest) error.value = toApiError(caught)
    } finally {
      if (request === latestRequest) loading.value = false
    }
  }

  return { data, error, loading, reload }
}
