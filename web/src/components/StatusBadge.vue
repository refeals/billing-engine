<script setup lang="ts">
import type { SubscriptionStatus } from '@/api/subscriptions'

defineProps<{ status: SubscriptionStatus }>()

// Literal class names (not built from the status) so Tailwind can see them.
const styles: Record<SubscriptionStatus, { label: string; classes: string }> = {
  trialing: { label: 'Trialing', classes: 'bg-status-trialing/10 text-status-trialing' },
  active: { label: 'Active', classes: 'bg-status-active/10 text-status-active' },
  past_due: { label: 'Past due', classes: 'bg-status-past-due/10 text-status-past-due' },
  paused: { label: 'Paused', classes: 'bg-status-paused/10 text-status-paused' },
  canceled: { label: 'Canceled', classes: 'bg-status-canceled/10 text-status-canceled' },
}
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium"
    :class="styles[status].classes"
    :data-status="status"
  >
    <span class="size-1.5 rounded-full bg-current" aria-hidden="true" />
    {{ styles[status].label }}
  </span>
</template>
