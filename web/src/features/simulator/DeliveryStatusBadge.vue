<script setup lang="ts">
import type { DeliveryStatus } from '@/api/simulatorEvents'
import BaseBadge from '@/components/BaseBadge.vue'

defineProps<{ status: DeliveryStatus }>()

const presentation: Record<
  DeliveryStatus,
  { label: string; tone: 'neutral' | 'success' | 'warning' | 'danger' | 'accent' }
> = {
  pending: { label: 'Pending', tone: 'warning' },
  delivered: { label: 'Delivered', tone: 'success' },
  dropped: { label: 'Dropped', tone: 'danger' },
}
</script>

<template>
  <BaseBadge :tone="presentation[status].tone" :data-status="status">
    {{ presentation[status].label }}
  </BaseBadge>
</template>
