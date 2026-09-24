<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute } from 'vue-router'

import { toApiError } from '@/api/errors'
import { fetchWebhookEvent, reprocessWebhookEvent } from '@/api/webhookEvents'
import AuditEventItem from '@/components/AuditEventItem.vue'
import BaseButton from '@/components/BaseButton.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import EmptyState from '@/components/EmptyState.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { formatDateTime } from '@/utils/format'
import { humanize } from '@/utils/text'
import WebhookStatusBadge from './WebhookStatusBadge.vue'

const route = useRoute()
const eventId = computed(() => String(route.params.id))

const { data: event, error, reload } = useAsyncData(() => fetchWebhookEvent(eventId.value))
reload()
watch(eventId, reload)

const confirming = ref(false)
const pending = ref(false)
const reprocessError = ref<string | null>(null)
const lastOutcome = ref<string | null>(null)

async function reprocess() {
  if (!event.value) return
  pending.value = true
  reprocessError.value = null
  try {
    const result = await reprocessWebhookEvent(event.value.id)
    event.value = result.webhook_event
    lastOutcome.value = result.status
    confirming.value = false
  } catch (caught) {
    reprocessError.value = toApiError(caught).message
  } finally {
    pending.value = false
  }
}

const payload = computed(() => JSON.stringify(event.value?.payload ?? {}, null, 2))
</script>

<template>
  <div class="space-y-6">
    <RouterLink to="/webhooks" class="text-sm text-accent hover:text-accent-strong">
      ← Webhook inbox
    </RouterLink>

    <p v-if="error" class="text-sm text-danger" role="alert">{{ error.message }}</p>

    <template v-if="event">
      <header class="rounded-lg border border-border bg-surface p-5">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div class="flex items-center gap-3">
              <h2 class="font-mono text-base font-semibold">{{ event.event_type }}</h2>
              <WebhookStatusBadge :status="event.processing_status" />
            </div>
            <p class="mt-1 font-mono text-xs text-ink-faint">
              {{ event.provider_event_id }} · {{ event.provider_object_id }}
            </p>
          </div>
          <BaseButton v-if="event.reprocessable" variant="primary" @click="confirming = true">
            Reprocess
          </BaseButton>
        </div>

        <p v-if="lastOutcome" class="mt-4 text-sm text-ink-muted" role="status">
          Reprocessed: {{ humanize(lastOutcome) }}.
        </p>
        <p
          v-if="event.last_error"
          class="mt-4 rounded-md bg-danger/5 px-3 py-2 font-mono text-xs text-danger"
        >
          {{ event.last_error }}
        </p>

        <dl class="mt-4 grid gap-4 text-sm sm:grid-cols-4">
          <div>
            <dt class="text-xs text-ink-faint">Sent by provider</dt>
            <dd>{{ formatDateTime(event.provider_created_at) }}</dd>
          </div>
          <div>
            <dt class="text-xs text-ink-faint">Received</dt>
            <dd>{{ formatDateTime(event.received_at) }}</dd>
          </div>
          <div>
            <dt class="text-xs text-ink-faint">Attempts</dt>
            <dd>{{ event.attempts }}</dd>
          </div>
          <div>
            <dt class="text-xs text-ink-faint">Duplicate deliveries</dt>
            <dd>{{ event.duplicate_deliveries_count }}</dd>
          </div>
        </dl>
      </header>

      <section class="rounded-lg border border-border bg-surface">
        <h3 class="border-b border-border px-5 py-3 text-sm font-semibold">What it changed</h3>
        <ul v-if="event.billing_events.length > 0">
          <AuditEventItem v-for="item in event.billing_events" :key="item.id" :event="item" />
        </ul>
        <EmptyState
          v-else
          title="No changes recorded"
          description="Ignored events and events that failed leave no business changes."
        />
      </section>

      <section class="rounded-lg border border-border bg-surface">
        <h3 class="border-b border-border px-5 py-3 text-sm font-semibold">Payload</h3>
        <pre class="overflow-x-auto p-5 font-mono text-xs">{{ payload }}</pre>
      </section>

      <ConfirmDialog
        v-model:open="confirming"
        title="Reprocess event"
        confirm-label="Reprocess"
        variant="primary"
        :pending="pending"
        :error="reprocessError"
        @confirm="reprocess"
      >
        <p>
          Runs the handler for this event again. Only events that failed or never finished can be
          reprocessed, so nothing is applied twice.
        </p>
      </ConfirmDialog>
    </template>
  </div>
</template>
