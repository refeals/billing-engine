<script setup lang="ts">
import { ref } from 'vue'

import { fetchClock } from '@/api/clock'
import { useClockRefresh } from '@/composables/useClockRefresh'
import { formatDateTime } from '@/utils/format'

const refreshedFor = ref<string | null>(null)

useClockRefresh(async () => {
  try {
    refreshedFor.value = (await fetchClock()).now
  } catch {
    // The header clock already reports API errors; nothing extra to show here.
    refreshedFor.value = null
  }
})
</script>

<template>
  <section class="max-w-2xl rounded-lg border border-border bg-surface p-6">
    <h2 class="text-base font-semibold">Billing health overview</h2>
    <p class="mt-2 text-sm text-ink-muted">
      Subscription counts, MRR, open dunning cases and reconciliation discrepancies will live here.
      Use the clock in the header to move simulated time forward; every screen reloads its data when
      time changes.
    </p>
    <p v-if="refreshedFor" class="mt-4 text-xs text-ink-faint">
      Data loaded for {{ formatDateTime(refreshedFor) }}
    </p>
  </section>
</template>
