<script setup lang="ts">
import { computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { fetchInvoices, INVOICE_STATUSES } from '@/api/invoices'
import EmptyState from '@/components/EmptyState.vue'
import PaginationNav from '@/components/PaginationNav.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockRefresh } from '@/composables/useClockRefresh'
import { formatDate, formatMoney } from '@/utils/format'
import { humanize } from '@/utils/text'
import InvoiceStatusBadge from './InvoiceStatusBadge.vue'

const route = useRoute()
const router = useRouter()

const status = computed(() => (typeof route.query.status === 'string' ? route.query.status : ''))
const page = computed(() => Number(route.query.page ?? 1) || 1)

const { data, error, loading, reload } = useAsyncData(() =>
  fetchInvoices({ status: status.value, page: page.value }),
)
const invoices = computed(() => data.value?.data ?? [])

useClockRefresh(reload)
// Leaving the page also changes the route; only react to changes made on this page.
watch(
  () => route.query,
  () => {
    if (route.name === 'invoices') reload()
  },
)

function setStatus(value: string) {
  router.replace({ query: { status: value || undefined } })
}

function goToPage(target: number) {
  router.replace({ query: { ...route.query, page: target > 1 ? String(target) : undefined } })
}

function openInvoice(id: number) {
  router.push({ name: 'invoice', params: { id } })
}
</script>

<template>
  <div class="space-y-4">
    <select
      :value="status"
      aria-label="Filter by status"
      class="rounded-md border border-border bg-surface px-2 py-1.5 text-sm"
      @change="setStatus(($event.target as HTMLSelectElement).value)"
    >
      <option value="">All statuses</option>
      <option v-for="option in INVOICE_STATUSES" :key="option" :value="option">
        {{ humanize(option) }}
      </option>
    </select>

    <p v-if="error" class="text-sm text-danger" role="alert">{{ error.message }}</p>

    <section
      class="overflow-x-auto rounded-lg border border-border bg-surface"
      :aria-busy="loading"
    >
      <table v-if="invoices.length > 0" class="w-full text-sm">
        <thead class="border-b border-border text-left text-xs text-ink-faint">
          <tr>
            <th class="px-4 py-2 font-medium">Invoice</th>
            <th class="px-4 py-2 font-medium">Customer</th>
            <th class="px-4 py-2 text-right font-medium">Total</th>
            <th class="px-4 py-2 text-right font-medium">Due</th>
            <th class="px-4 py-2 font-medium">Status</th>
            <th class="px-4 py-2 font-medium">Issued</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="invoice in invoices"
            :key="invoice.id"
            class="cursor-pointer border-b border-border last:border-b-0 hover:bg-canvas"
            @click="openInvoice(invoice.id)"
          >
            <td class="px-4 py-3">
              <RouterLink
                :to="{ name: 'invoice', params: { id: invoice.id } }"
                class="font-mono text-sm hover:text-accent"
                @click.stop
              >
                {{ invoice.number }}
              </RouterLink>
              <p class="text-xs text-ink-faint">{{ humanize(invoice.billing_reason) }}</p>
            </td>
            <td class="px-4 py-3">{{ invoice.customer.name }}</td>
            <td class="px-4 py-3 text-right tabular-nums">
              {{ formatMoney(invoice.total_cents) }}
            </td>
            <td class="px-4 py-3 text-right tabular-nums">
              {{ invoice.amount_due_cents > 0 ? formatMoney(invoice.amount_due_cents) : '—' }}
            </td>
            <td class="px-4 py-3"><InvoiceStatusBadge :status="invoice.status" /></td>
            <td class="px-4 py-3 text-ink-muted">{{ formatDate(invoice.issued_at) }}</td>
          </tr>
        </tbody>
      </table>

      <EmptyState
        v-else-if="!loading && !error"
        :title="status ? 'No invoices with this status' : 'No invoices yet'"
        description="Invoices are issued when a subscription starts without a trial, when a trial ends and at each renewal."
      />
    </section>

    <PaginationNav
      v-if="data"
      :meta="data.meta"
      noun="invoices"
      :disabled="loading"
      @change="goToPage"
    />
  </div>
</template>
