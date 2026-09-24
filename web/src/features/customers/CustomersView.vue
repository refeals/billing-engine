<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { fetchCustomers, type CustomerDetail } from '@/api/customers'
import BaseButton from '@/components/BaseButton.vue'
import EmptyState from '@/components/EmptyState.vue'
import PaginationNav from '@/components/PaginationNav.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockRefresh } from '@/composables/useClockRefresh'
import { formatDate, formatMoney } from '@/utils/format'
import CustomerFormDialog from './CustomerFormDialog.vue'

const route = useRoute()
const router = useRouter()

// Search and page live in the URL so a filtered list can be shared or bookmarked.
const query = computed(() => (typeof route.query.q === 'string' ? route.query.q : ''))
const page = computed(() => Number(route.query.page ?? 1) || 1)
const search = ref(query.value)
const creating = ref(false)

const { data, error, loading, reload } = useAsyncData(() =>
  fetchCustomers({ q: query.value, page: page.value }),
)
const customers = computed(() => data.value?.data ?? [])

let debounce: ReturnType<typeof setTimeout> | undefined
watch(search, (value) => {
  clearTimeout(debounce)
  debounce = setTimeout(() => {
    router.replace({ query: { q: value.trim() || undefined } })
  }, 300)
})
onBeforeUnmount(() => clearTimeout(debounce))

useClockRefresh(reload)
// Leaving the page also changes the route; only react to changes made on this page.
watch(
  () => route.query,
  () => {
    if (route.name === 'customers') reload()
  },
)

function goToPage(target: number) {
  router.replace({ query: { ...route.query, page: target > 1 ? String(target) : undefined } })
}

function openCustomer(customer: { id: number }) {
  router.push({ name: 'customer', params: { id: customer.id } })
}

function onCreated(customer: CustomerDetail) {
  openCustomer(customer)
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <input
        v-model="search"
        type="search"
        placeholder="Search by name or email"
        aria-label="Search customers"
        class="w-full max-w-xs rounded-md border border-border bg-surface px-3 py-1.5 text-sm"
      />
      <BaseButton variant="primary" @click="creating = true">New customer</BaseButton>
    </div>

    <p v-if="error" class="text-sm text-danger" role="alert">{{ error.message }}</p>

    <section
      class="overflow-x-auto rounded-lg border border-border bg-surface"
      :aria-busy="loading"
    >
      <table v-if="customers.length > 0" class="w-full text-sm">
        <thead class="border-b border-border text-left text-xs text-ink-faint">
          <tr>
            <th class="px-4 py-2 font-medium">Customer</th>
            <th class="px-4 py-2 font-medium">Credit balance</th>
            <th class="px-4 py-2 font-medium">Created</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="customer in customers"
            :key="customer.id"
            class="cursor-pointer border-b border-border last:border-b-0 hover:bg-canvas"
            @click="openCustomer(customer)"
          >
            <td class="px-4 py-3">
              <RouterLink
                :to="{ name: 'customer', params: { id: customer.id } }"
                class="font-medium hover:text-accent"
                @click.stop
              >
                {{ customer.name }}
              </RouterLink>
              <p class="text-xs text-ink-faint">{{ customer.email }}</p>
            </td>
            <td class="px-4 py-3 tabular-nums">{{ formatMoney(customer.credit_balance_cents) }}</td>
            <td class="px-4 py-3 text-ink-muted">{{ formatDate(customer.created_at) }}</td>
          </tr>
        </tbody>
      </table>

      <EmptyState
        v-else-if="!loading && !error"
        :title="query ? 'No customers match this search' : 'No customers yet'"
        :description="
          query
            ? 'Try part of the studio name or email.'
            : 'Customers are the studios that subscribe to a plan.'
        "
      >
        <BaseButton v-if="!query" variant="primary" @click="creating = true">
          Add the first customer
        </BaseButton>
      </EmptyState>
    </section>

    <PaginationNav
      v-if="data"
      :meta="data.meta"
      noun="customers"
      :disabled="loading"
      @change="goToPage"
    />

    <CustomerFormDialog v-model:open="creating" @created="onCreated" />
  </div>
</template>
