<script setup lang="ts">
import { computed, ref, watch } from 'vue'

import { toApiError } from '@/api/errors'
import {
  DELIVERY_STATUSES,
  deliverProviderEvent,
  fetchProviderEvents,
  type ProviderEvent,
} from '@/api/simulatorEvents'
import BaseButton from '@/components/BaseButton.vue'
import EmptyState from '@/components/EmptyState.vue'
import PaginationNav from '@/components/PaginationNav.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockRefresh } from '@/composables/useClockRefresh'
import { formatDateTime } from '@/utils/format'
import { humanize } from '@/utils/text'
import DeliveryStatusBadge from './DeliveryStatusBadge.vue'
import EmitEventForm from './EmitEventForm.vue'

const statusFilter = ref('')
const page = ref(1)

const { data, error, loading, reload } = useAsyncData(() =>
  fetchProviderEvents({ delivery_status: statusFilter.value, page: page.value }),
)
const events = computed(() => data.value?.data ?? [])

useClockRefresh(reload)
watch(page, reload)
watch(statusFilter, () => {
  page.value = 1
  reload()
})

const deliveringId = ref<number | null>(null)
const actionError = ref<string | null>(null)

async function deliver(event: ProviderEvent) {
  deliveringId.value = event.id
  actionError.value = null
  try {
    await deliverProviderEvent(event.id)
    await reload()
  } catch (caught) {
    actionError.value = toApiError(caught).message
  } finally {
    deliveringId.value = null
  }
}

function onEmitted() {
  page.value = 1
  reload()
}
</script>

<template>
  <div class="space-y-6">
    <EmitEventForm @emitted="onEmitted" />

    <section class="space-y-3">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 class="text-sm font-semibold">Provider outbox</h2>
          <p class="text-sm text-ink-muted">
            Everything the fake Stripe emitted, delivered or not. It never reads the engine's
            tables, so it is an independent record of what the provider believes.
          </p>
        </div>
        <select
          v-model="statusFilter"
          aria-label="Filter by delivery status"
          class="rounded-md border border-border bg-surface px-2 py-1.5 text-sm"
        >
          <option value="">All deliveries</option>
          <option v-for="status in DELIVERY_STATUSES" :key="status" :value="status">
            {{ humanize(status) }}
          </option>
        </select>
      </div>

      <p v-if="error || actionError" class="text-sm text-danger" role="alert">
        {{ actionError ?? error?.message }}
      </p>

      <div class="overflow-x-auto rounded-lg border border-border bg-surface" :aria-busy="loading">
        <table v-if="events.length > 0" class="w-full text-sm">
          <thead class="border-b border-border text-left text-xs text-ink-faint">
            <tr>
              <th class="px-4 py-2 font-medium">Event</th>
              <th class="px-4 py-2 font-medium">Delivery</th>
              <th class="px-4 py-2 font-medium">Inbox result</th>
              <th class="px-4 py-2 font-medium">Emitted</th>
              <th class="px-4 py-2"><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="event in events"
              :key="event.id"
              class="border-b border-border last:border-b-0"
            >
              <td class="px-4 py-3">
                <p class="font-mono text-sm">{{ event.event_type }}</p>
                <p class="font-mono text-xs text-ink-faint">
                  {{ event.event_id }} · {{ event.provider_object_id }}
                </p>
              </td>
              <td class="px-4 py-3">
                <div class="flex flex-wrap items-center gap-2">
                  <DeliveryStatusBadge :status="event.delivery_status" />
                  <span v-if="event.delivery_count > 0" class="text-xs text-ink-muted">
                    sent {{ event.delivery_count }}×
                  </span>
                </div>
              </td>
              <td class="px-4 py-3">
                <RouterLink
                  v-if="event.webhook_event_id"
                  :to="{ name: 'webhook-event', params: { id: event.webhook_event_id } }"
                  class="text-accent hover:text-accent-strong"
                >
                  {{ humanize(event.last_delivery_result ?? 'delivered') }} →
                </RouterLink>
                <span v-else class="text-ink-faint">
                  {{ event.last_delivery_result ? humanize(event.last_delivery_result) : '—' }}
                </span>
              </td>
              <td class="px-4 py-3 text-ink-muted">
                {{ formatDateTime(event.provider_created_at) }}
              </td>
              <td class="px-4 py-3 text-right">
                <BaseButton
                  v-if="event.delivery_status !== 'pending'"
                  variant="ghost"
                  :disabled="deliveringId === event.id"
                  @click="deliver(event)"
                >
                  {{ event.delivery_status === 'dropped' ? 'Deliver now' : 'Redeliver' }}
                </BaseButton>
              </td>
            </tr>
          </tbody>
        </table>

        <EmptyState
          v-else-if="!loading && !error"
          title="The provider hasn't emitted anything yet"
          description="Creating customers, cards and subscriptions makes it report them."
        />
      </div>

      <PaginationNav
        v-if="data"
        :meta="data.meta"
        noun="events"
        :disabled="loading"
        @change="page = $event"
      />
    </section>
  </div>
</template>
