<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { fetchSubscriptions, SUBSCRIPTION_STATUSES, type Subscription } from '@/api/subscriptions'
import BaseButton from '@/components/BaseButton.vue'
import EmptyState from '@/components/EmptyState.vue'
import PaginationNav from '@/components/PaginationNav.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockRefresh } from '@/composables/useClockRefresh'
import { formatDate } from '@/utils/format'
import { humanize } from '@/utils/text'
import NewSubscriptionDialog from './NewSubscriptionDialog.vue'

const route = useRoute()
const router = useRouter()

// Filters live in the URL so a filtered list can be shared or bookmarked.
const status = computed(() => (typeof route.query.status === 'string' ? route.query.status : ''))
const query = computed(() => (typeof route.query.q === 'string' ? route.query.q : ''))
const page = computed(() => Number(route.query.page ?? 1) || 1)
const search = ref(query.value)
const creating = ref(false)

const { data, error, loading, reload } = useAsyncData(() =>
  fetchSubscriptions({ status: status.value, q: query.value, page: page.value }),
)
const subscriptions = computed(() => data.value?.data ?? [])
const hasFilters = computed(() => status.value !== '' || query.value !== '')

let debounce: ReturnType<typeof setTimeout> | undefined
watch(search, (value) => {
  clearTimeout(debounce)
  debounce = setTimeout(() => {
    router.replace({ query: { ...route.query, q: value.trim() || undefined, page: undefined } })
  }, 300)
})
onBeforeUnmount(() => clearTimeout(debounce))

useClockRefresh(reload)
// Leaving the page also changes the route; only react to changes made on this page.
watch(
  () => route.query,
  () => {
    if (route.name === 'subscriptions') reload()
  },
)

function setStatus(value: string) {
  router.replace({ query: { ...route.query, status: value || undefined, page: undefined } })
}

function goToPage(target: number) {
  router.replace({ query: { ...route.query, page: target > 1 ? String(target) : undefined } })
}

// The date that matters most for each state, in one column.
function nextDate(subscription: Subscription): string {
  if (subscription.status === 'canceled' && subscription.canceled_at) {
    return `Canceled ${formatDate(subscription.canceled_at)}`
  }
  if (subscription.status === 'paused') {
    return subscription.resumes_at ? `Resumes ${formatDate(subscription.resumes_at)}` : 'Paused'
  }
  if (subscription.cancel_at_period_end) {
    return `Cancels ${formatDate(subscription.current_period_end)}`
  }
  if (subscription.status === 'trialing' && subscription.trial_ends_at) {
    return `Trial ends ${formatDate(subscription.trial_ends_at)}`
  }
  return `Renews ${formatDate(subscription.current_period_end)}`
}

function openSubscription(subscription: { id: number }) {
  router.push({ name: 'subscription', params: { id: subscription.id } })
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="flex flex-wrap items-center gap-3">
        <input
          v-model="search"
          type="search"
          placeholder="Search by customer"
          aria-label="Search subscriptions by customer"
          class="w-64 rounded-md border border-border bg-surface px-3 py-1.5 text-sm"
        />
        <select
          :value="status"
          aria-label="Filter by status"
          class="rounded-md border border-border bg-surface px-2 py-1.5 text-sm"
          @change="setStatus(($event.target as HTMLSelectElement).value)"
        >
          <option value="">All statuses</option>
          <option v-for="option in SUBSCRIPTION_STATUSES" :key="option" :value="option">
            {{ humanize(option) }}
          </option>
        </select>
      </div>
      <BaseButton variant="primary" @click="creating = true">New subscription</BaseButton>
    </div>

    <p v-if="error" class="text-sm text-danger" role="alert">{{ error.message }}</p>

    <section
      class="overflow-x-auto rounded-lg border border-border bg-surface"
      :aria-busy="loading"
    >
      <table v-if="subscriptions.length > 0" class="w-full text-sm">
        <thead class="border-b border-border text-left text-xs text-ink-faint">
          <tr>
            <th class="px-4 py-2 font-medium">Customer</th>
            <th class="px-4 py-2 font-medium">Plan</th>
            <th class="px-4 py-2 font-medium">Status</th>
            <th class="px-4 py-2 font-medium">Next</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="subscription in subscriptions"
            :key="subscription.id"
            class="cursor-pointer border-b border-border last:border-b-0 hover:bg-canvas"
            @click="openSubscription(subscription)"
          >
            <td class="px-4 py-3">
              <RouterLink
                :to="{ name: 'subscription', params: { id: subscription.id } }"
                class="font-medium hover:text-accent"
                @click.stop
              >
                {{ subscription.customer.name }}
              </RouterLink>
              <p class="text-xs text-ink-faint">{{ subscription.customer.email }}</p>
            </td>
            <td class="px-4 py-3">{{ subscription.plan.name }}</td>
            <td class="px-4 py-3"><StatusBadge :status="subscription.status" /></td>
            <td class="px-4 py-3 text-ink-muted">{{ nextDate(subscription) }}</td>
          </tr>
        </tbody>
      </table>

      <EmptyState
        v-else-if="!loading && !error"
        :title="hasFilters ? 'No subscriptions match' : 'No subscriptions yet'"
        :description="
          hasFilters
            ? 'Try another status or search.'
            : 'Subscribe a customer to a plan to start a billing lifecycle.'
        "
      >
        <BaseButton v-if="!hasFilters" variant="primary" @click="creating = true">
          Create the first subscription
        </BaseButton>
      </EmptyState>
    </section>

    <PaginationNav
      v-if="data"
      :meta="data.meta"
      noun="subscriptions"
      :disabled="loading"
      @change="goToPage"
    />

    <NewSubscriptionDialog v-model:open="creating" @created="openSubscription" />
  </div>
</template>
