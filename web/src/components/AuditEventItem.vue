<script setup lang="ts">
import { computed, ref } from 'vue'

import type { BillingEvent } from '@/api/billingEvents'
import JsonDiff from '@/components/JsonDiff.vue'
import { formatDateTime } from '@/utils/format'

const props = defineProps<{ event: BillingEvent }>()

const expanded = ref(false)

const actorLabels: Record<BillingEvent['actor_type'], string> = {
  admin: 'Admin',
  webhook: 'Webhook',
  system_job: 'System',
  reconciliation: 'Reconciliation',
}

const subjectLabel = computed(() => {
  const subject = props.event.subject
  return subject ? `${subject.type} #${subject.id}` : null
})
</script>

<template>
  <li class="border-b border-border last:border-b-0">
    <button
      type="button"
      class="flex w-full flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3 text-left hover:bg-canvas"
      :aria-expanded="expanded"
      @click="expanded = !expanded"
    >
      <span class="w-44 shrink-0 text-xs text-ink-muted tabular-nums">
        {{ formatDateTime(event.occurred_at) }}
      </span>
      <span class="font-mono text-sm">{{ event.event_type }}</span>
      <span class="rounded-full bg-canvas px-2 py-0.5 text-xs text-ink-muted">
        {{ actorLabels[event.actor_type] }}
      </span>
      <span v-if="subjectLabel" class="text-xs text-ink-faint">{{ subjectLabel }}</span>
      <span class="ml-auto text-xs text-ink-faint">{{ expanded ? 'Hide' : 'Details' }}</span>
    </button>

    <div v-if="expanded" class="space-y-3 px-4 pb-4">
      <RouterLink
        v-if="event.webhook_event_id"
        :to="{ name: 'webhook-event', params: { id: event.webhook_event_id } }"
        class="inline-block text-xs text-accent hover:text-accent-strong"
      >
        Caused by webhook event #{{ event.webhook_event_id }} →
      </RouterLink>
      <JsonDiff
        :before="event.data.before"
        :after="event.data.after"
        :context="event.data.context"
      />
    </div>
  </li>
</template>
