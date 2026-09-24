<script setup lang="ts">
import type { InvoiceStatus } from '@/api/invoices'
import BaseBadge from '@/components/BaseBadge.vue'

defineProps<{ status: InvoiceStatus }>()

const presentation: Record<
  InvoiceStatus,
  { label: string; tone: 'neutral' | 'success' | 'warning' | 'danger' | 'accent' }
> = {
  open: { label: 'Open', tone: 'warning' },
  paid: { label: 'Paid', tone: 'success' },
  void: { label: 'Void', tone: 'neutral' },
  uncollectible: { label: 'Uncollectible', tone: 'danger' },
}
</script>

<template>
  <BaseBadge :tone="presentation[status].tone" :data-status="status">
    {{ presentation[status].label }}
  </BaseBadge>
</template>
