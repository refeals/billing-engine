<script setup lang="ts">
import { computed, onMounted } from 'vue'

import { useClockStore } from '@/stores/clock'
import { formatDate } from '@/utils/format'

const clock = useClockStore()
const steps = [1, 3, 7]

onMounted(clock.load)

const lastAdvanceSummary = computed(() => {
  const result = clock.lastAdvance
  if (!result) return null

  const days = `${result.ticks_run} ${result.ticks_run === 1 ? 'day' : 'days'}`
  const work = Object.entries(result.tick_report).filter(([, count]) => count > 0)
  if (work.length === 0) return `Advanced ${days}. No scheduled work was due.`

  const details = work.map(([counter, count]) => `${count} ${counter.replaceAll('_', ' ')}`)
  return `Advanced ${days}: ${details.join(', ')}.`
})
</script>

<template>
  <div class="flex flex-col items-end gap-1">
    <div class="flex items-center gap-2">
      <div class="text-right">
        <p class="text-[11px] tracking-wide text-ink-faint uppercase">Simulated date</p>
        <p class="text-sm font-semibold tabular-nums" data-testid="clock-now">
          {{ clock.now ? formatDate(clock.now) : '—' }}
        </p>
      </div>

      <div class="flex overflow-hidden rounded-md border border-border">
        <button
          v-for="days in steps"
          :key="days"
          type="button"
          class="border-r border-border px-2.5 py-1.5 text-sm font-medium hover:bg-canvas disabled:opacity-50"
          :disabled="clock.pending"
          @click="clock.advance(days)"
        >
          +{{ days }}d
        </button>
        <button
          type="button"
          class="px-2.5 py-1.5 text-sm text-ink-muted hover:bg-canvas disabled:opacity-50"
          :disabled="clock.pending"
          title="Move the clock back to real time"
          @click="clock.reset()"
        >
          Reset
        </button>
      </div>
    </div>

    <p v-if="clock.error" class="text-xs text-danger" role="alert">{{ clock.error.message }}</p>
    <p v-else-if="lastAdvanceSummary" class="text-xs text-ink-muted" aria-live="polite">
      {{ lastAdvanceSummary }}
    </p>
  </div>
</template>
