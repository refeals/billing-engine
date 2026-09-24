<script setup lang="ts">
import type { WebhookStatus } from '@/api/webhookEvents'
import BaseBadge from '@/components/BaseBadge.vue'

defineProps<{ status: WebhookStatus }>()

const presentation: Record<
  WebhookStatus,
  { label: string; tone: 'neutral' | 'success' | 'warning' | 'danger' | 'accent' }
> = {
  received: { label: 'Received', tone: 'accent' },
  processed: { label: 'Processed', tone: 'success' },
  failed: { label: 'Failed', tone: 'danger' },
  skipped_stale: { label: 'Skipped (stale)', tone: 'warning' },
  ignored_unhandled: { label: 'Ignored', tone: 'neutral' },
}
</script>

<template>
  <BaseBadge :tone="presentation[status].tone" :data-status="status">
    {{ presentation[status].label }}
  </BaseBadge>
</template>
