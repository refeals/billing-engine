<script setup lang="ts">
import { computed } from 'vue'

import {
  boardColumn,
  fetchDunningCases,
  STEP_LABELS,
  type BoardColumn,
  type DunningCase,
} from '@/api/dunning'
import BaseBadge from '@/components/BaseBadge.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockRefresh } from '@/composables/useClockRefresh'
import { formatDate, formatMoney } from '@/utils/format'
import { humanize } from '@/utils/text'

const openCases = useAsyncData(() => fetchDunningCases({ status: 'open' }))
const closedCases = useAsyncData(() => fetchDunningCases({ status: 'closed' }))

// The board is about what the clock does to these cases: reload whenever time moves.
useClockRefresh(() => {
  openCases.reload()
  closedCases.reload()
})

const columns: { key: BoardColumn; title: string; hint: string }[] = [
  { key: 'notified', title: 'Notified', hint: 'Payment failed; retry on day 3' },
  { key: 'retried', title: 'Retried', hint: 'Retry failed; access suspended on day 7' },
  { key: 'suspended', title: 'Suspended', hint: 'Access suspended; canceled on day 14' },
  { key: 'recovered', title: 'Recovered', hint: 'Paid before the end' },
  { key: 'lost', title: 'Canceled', hint: 'Exhausted, or canceled meanwhile' },
]

const byColumn = computed(() => {
  const grouped = Object.fromEntries(
    columns.map((column) => [column.key, [] as DunningCase[]]),
  ) as Record<BoardColumn, DunningCase[]>
  for (const dunningCase of [
    ...(openCases.data.value?.data ?? []),
    ...(closedCases.data.value?.data ?? []),
  ]) {
    grouped[boardColumn(dunningCase)].push(dunningCase)
  }
  return grouped
})

const error = computed(() => openCases.error.value ?? closedCases.error.value)
</script>

<template>
  <div class="space-y-4">
    <p class="max-w-3xl text-sm text-ink-muted">
      Every failed payment follows the same schedule: a notice on day 0, a retry on day 3, access
      suspended on day 7 and cancellation on day 14. Paying at any point ends it. Advance the clock
      to watch cases move.
    </p>

    <p v-if="error" class="text-sm text-danger" role="alert">{{ error.message }}</p>

    <div class="grid gap-4 overflow-x-auto md:grid-cols-5">
      <section
        v-for="column in columns"
        :key="column.key"
        class="min-w-52 rounded-lg border border-border bg-surface"
      >
        <header class="border-b border-border px-3 py-2">
          <p class="text-sm font-semibold">
            {{ column.title }}
            <span class="ml-1 text-ink-faint">{{ byColumn[column.key].length }}</span>
          </p>
          <p class="text-xs text-ink-faint">{{ column.hint }}</p>
        </header>
        <ul class="space-y-2 p-2">
          <li v-for="dunningCase in byColumn[column.key]" :key="dunningCase.id">
            <RouterLink
              :to="{ name: 'subscription', params: { id: dunningCase.subscription_id } }"
              class="block rounded-md border border-border p-2 text-sm hover:border-accent"
            >
              <p class="font-medium">{{ dunningCase.customer.name }}</p>
              <p class="text-xs text-ink-muted">
                {{ dunningCase.invoice.number }} ·
                {{ formatMoney(dunningCase.invoice.total_cents) }}
              </p>
              <p
                v-if="dunningCase.next_step && dunningCase.next_step_at"
                class="mt-1 text-xs text-ink-faint"
              >
                Next: {{ STEP_LABELS[dunningCase.next_step] }} on
                {{ formatDate(dunningCase.next_step_at) }}
              </p>
              <p v-else-if="dunningCase.closed_at" class="mt-1 text-xs text-ink-faint">
                {{ humanize(dunningCase.closed_reason ?? dunningCase.status) }} on
                {{ formatDate(dunningCase.closed_at) }}
              </p>
              <BaseBadge v-if="dunningCase.access_suspended" tone="danger" class="mt-1"
                >Access suspended</BaseBadge
              >
            </RouterLink>
          </li>
          <li
            v-if="byColumn[column.key].length === 0"
            class="px-1 py-3 text-center text-xs text-ink-faint"
          >
            None
          </li>
        </ul>
      </section>
    </div>
  </div>
</template>
