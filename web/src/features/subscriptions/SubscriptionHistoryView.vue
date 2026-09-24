<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute } from 'vue-router'

import { fetchBillingEvents } from '@/api/billingEvents'
import AuditEventItem from '@/components/AuditEventItem.vue'
import EmptyState from '@/components/EmptyState.vue'
import PaginationNav from '@/components/PaginationNav.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockRefresh } from '@/composables/useClockRefresh'

const route = useRoute()
const subscriptionId = computed(() => String(route.params.id))
const page = ref(1)

// Every status change is also a billing event, so the audit log filtered by subscription
// is the complete, immutable history of this subscription.
const { data, error, loading, reload } = useAsyncData(() =>
  fetchBillingEvents({ subscription_id: subscriptionId.value, page: String(page.value) }),
)

useClockRefresh(reload)
watch(page, reload)
watch(subscriptionId, () => {
  page.value = 1
  reload()
})
</script>

<template>
  <div class="space-y-4">
    <RouterLink
      :to="{ name: 'subscription', params: { id: subscriptionId } }"
      class="text-sm text-accent hover:text-accent-strong"
    >
      ← Back to subscription
    </RouterLink>

    <p class="max-w-3xl text-sm text-ink-muted">
      Everything that happened to this subscription, newest first. These records are append-only:
      the database refuses to change or delete them.
    </p>

    <p v-if="error" class="text-sm text-danger" role="alert">{{ error.message }}</p>

    <section class="rounded-lg border border-border bg-surface" :aria-busy="loading">
      <ul v-if="data && data.data.length > 0">
        <AuditEventItem v-for="event in data.data" :key="event.id" :event="event" />
      </ul>
      <EmptyState v-else-if="!loading && !error" title="No history yet" />
    </section>

    <PaginationNav
      v-if="data"
      :meta="data.meta"
      noun="events"
      :disabled="loading"
      @change="page = $event"
    />
  </div>
</template>
