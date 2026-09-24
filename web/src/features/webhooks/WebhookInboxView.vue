<script setup lang="ts">
import { computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { fetchWebhookEvents, WEBHOOK_STATUSES } from '@/api/webhookEvents'
import BaseBadge from '@/components/BaseBadge.vue'
import EmptyState from '@/components/EmptyState.vue'
import PaginationNav from '@/components/PaginationNav.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockRefresh } from '@/composables/useClockRefresh'
import { formatDateTime } from '@/utils/format'
import { humanize } from '@/utils/text'
import WebhookStatusBadge from './WebhookStatusBadge.vue'

const route = useRoute()
const router = useRouter()

const status = computed(() => (typeof route.query.status === 'string' ? route.query.status : ''))
const page = computed(() => Number(route.query.page ?? 1) || 1)

const { data, error, loading, reload } = useAsyncData(() =>
  fetchWebhookEvents({ status: status.value, page: page.value }),
)
const events = computed(() => data.value?.data ?? [])

useClockRefresh(reload)
// Leaving the page also changes the route; only react to changes made on this page.
watch(
  () => route.query,
  () => {
    if (route.name === 'webhooks') reload()
  },
)

function setStatus(value: string) {
  router.replace({ query: { status: value || undefined } })
}

function goToPage(target: number) {
  router.replace({ query: { ...route.query, page: target > 1 ? String(target) : undefined } })
}

function openEvent(id: number) {
  router.push({ name: 'webhook-event', params: { id } })
}
</script>

<template>
  <div class="space-y-4">
    <p class="max-w-3xl text-sm text-ink-muted">
      Every event the payment provider sent, one row per event id. A redelivered event is counted as
      a duplicate and never applied twice.
    </p>

    <select
      :value="status"
      aria-label="Filter by status"
      class="rounded-md border border-border bg-surface px-2 py-1.5 text-sm"
      @change="setStatus(($event.target as HTMLSelectElement).value)"
    >
      <option value="">All statuses</option>
      <option v-for="option in WEBHOOK_STATUSES" :key="option" :value="option">
        {{ humanize(option) }}
      </option>
    </select>

    <p v-if="error" class="text-sm text-danger" role="alert">{{ error.message }}</p>

    <section
      class="overflow-x-auto rounded-lg border border-border bg-surface"
      :aria-busy="loading"
    >
      <table v-if="events.length > 0" class="w-full text-sm">
        <thead class="border-b border-border text-left text-xs text-ink-faint">
          <tr>
            <th class="px-4 py-2 font-medium">Event</th>
            <th class="px-4 py-2 font-medium">Object</th>
            <th class="px-4 py-2 font-medium">Status</th>
            <th class="px-4 py-2 text-right font-medium">Attempts</th>
            <th class="px-4 py-2 font-medium">Received</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="event in events"
            :key="event.id"
            class="cursor-pointer border-b border-border last:border-b-0 hover:bg-canvas"
            @click="openEvent(event.id)"
          >
            <td class="px-4 py-3">
              <RouterLink
                :to="{ name: 'webhook-event', params: { id: event.id } }"
                class="font-mono text-sm hover:text-accent"
                @click.stop
              >
                {{ event.event_type }}
              </RouterLink>
              <p class="font-mono text-xs text-ink-faint">{{ event.provider_event_id }}</p>
            </td>
            <td class="px-4 py-3 font-mono text-xs text-ink-muted">
              {{ event.provider_object_id }}
            </td>
            <td class="px-4 py-3">
              <div class="flex flex-wrap items-center gap-2">
                <WebhookStatusBadge :status="event.processing_status" />
                <BaseBadge
                  v-if="event.duplicate_deliveries_count > 0"
                  :title="`Delivered ${event.duplicate_deliveries_count} more time(s), ignored`"
                >
                  +{{ event.duplicate_deliveries_count }} duplicate
                </BaseBadge>
              </div>
            </td>
            <td class="px-4 py-3 text-right tabular-nums">{{ event.attempts }}</td>
            <td class="px-4 py-3 text-ink-muted">{{ formatDateTime(event.received_at) }}</td>
          </tr>
        </tbody>
      </table>

      <EmptyState
        v-else-if="!loading && !error"
        :title="status ? 'No events with this status' : 'No webhook events yet'"
        description="Events arrive at POST /api/v1/webhooks/stripe."
      />
    </section>

    <PaginationNav
      v-if="data"
      :meta="data.meta"
      noun="events"
      :disabled="loading"
      @change="goToPage"
    />
  </div>
</template>
