<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import {
  fetchCreditLedger,
  fetchCustomer,
  makeDefaultPaymentMethod,
  type PaymentMethod,
} from '@/api/customers'
import { toApiError } from '@/api/errors'
import type { Subscription } from '@/api/subscriptions'
import BaseBadge from '@/components/BaseBadge.vue'
import BaseButton from '@/components/BaseButton.vue'
import EmptyState from '@/components/EmptyState.vue'
import PaginationNav from '@/components/PaginationNav.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockRefresh } from '@/composables/useClockRefresh'
import { formatDate, formatMoney } from '@/utils/format'
import { humanize } from '@/utils/text'
import NewSubscriptionDialog from '@/features/subscriptions/NewSubscriptionDialog.vue'
import CreditAdjustmentDialog from './CreditAdjustmentDialog.vue'
import PaymentMethodDialog from './PaymentMethodDialog.vue'

const route = useRoute()
const customerId = computed(() => String(route.params.id))
const ledgerPage = ref(1)

const customerData = useAsyncData(() => fetchCustomer(customerId.value))
const ledgerData = useAsyncData(() => fetchCreditLedger(customerId.value, ledgerPage.value))
const customer = computed(() => customerData.data.value)
const ledger = computed(() => ledgerData.data.value)

function reloadAll() {
  customerData.reload()
  ledgerData.reload()
}

// Expired badges depend on the simulated date, so time moving means reloading.
useClockRefresh(reloadAll)
watch(customerId, () => {
  ledgerPage.value = 1
  reloadAll()
})
watch(ledgerPage, ledgerData.reload)

const router = useRouter()
const subscribing = ref(false)
// The API allows one live subscription per customer; the button follows the same rule.
const hasLiveSubscription = computed(
  () =>
    customer.value?.subscriptions.some((subscription) => subscription.status !== 'canceled') ??
    false,
)

function onSubscribed(subscription: Subscription) {
  router.push({ name: 'subscription', params: { id: subscription.id } })
}

const addingCard = ref(false)
const adjustingCredit = ref(false)
const cardActionError = ref<string | null>(null)

async function makeDefault(paymentMethod: PaymentMethod) {
  if (!customer.value) return
  cardActionError.value = null
  try {
    await makeDefaultPaymentMethod(customer.value.id, paymentMethod.id)
    await customerData.reload()
  } catch (caught) {
    cardActionError.value = toApiError(caught).message
  }
}

function brandLabel(brand: string) {
  return humanize(brand)
}

function expiry(paymentMethod: PaymentMethod) {
  return `${String(paymentMethod.exp_month).padStart(2, '0')}/${paymentMethod.exp_year}`
}
</script>

<template>
  <div class="space-y-6">
    <RouterLink to="/customers" class="text-sm text-accent hover:text-accent-strong">
      ← All customers
    </RouterLink>

    <p v-if="customerData.error.value" class="text-sm text-danger" role="alert">
      {{ customerData.error.value.message }}
    </p>

    <template v-if="customer">
      <header class="rounded-lg border border-border bg-surface p-5">
        <h2 class="text-lg font-semibold">{{ customer.name }}</h2>
        <p class="text-sm text-ink-muted">{{ customer.email }}</p>
        <p class="mt-2 font-mono text-xs text-ink-faint">
          {{ customer.provider_customer_id }} · customer since {{ formatDate(customer.created_at) }}
        </p>
      </header>

      <div class="grid gap-6 lg:grid-cols-2">
        <section class="rounded-lg border border-border bg-surface">
          <div class="flex items-center justify-between border-b border-border px-5 py-3">
            <h3 class="text-sm font-semibold">Payment methods</h3>
            <BaseButton @click="addingCard = true">Add test card</BaseButton>
          </div>

          <ul v-if="customer.payment_methods.length > 0">
            <li
              v-for="card in customer.payment_methods"
              :key="card.id"
              class="flex flex-wrap items-center gap-3 border-b border-border px-5 py-3 last:border-b-0"
            >
              <div class="min-w-0 flex-1">
                <p class="text-sm font-medium">
                  {{ brandLabel(card.brand) }} ···· {{ card.last4 }}
                </p>
                <p class="text-xs text-ink-muted">
                  Expires {{ expiry(card) }} · {{ humanize(card.behavior) }}
                </p>
              </div>
              <BaseBadge v-if="card.is_default" tone="accent">Default</BaseBadge>
              <BaseBadge v-if="card.expired" tone="danger">Expired</BaseBadge>
              <BaseButton v-if="!card.is_default" variant="ghost" @click="makeDefault(card)">
                Make default
              </BaseButton>
            </li>
          </ul>
          <EmptyState
            v-else
            title="No cards yet"
            description="Renewals need a default card to charge."
          />
          <p v-if="cardActionError" class="px-5 pb-3 text-sm text-danger" role="alert">
            {{ cardActionError }}
          </p>
        </section>

        <section class="rounded-lg border border-border bg-surface">
          <div class="flex items-center justify-between border-b border-border px-5 py-3">
            <div>
              <h3 class="text-sm font-semibold">Credit balance</h3>
              <p class="text-xl font-semibold tabular-nums">
                {{ formatMoney(customer.credit_balance_cents) }}
              </p>
            </div>
            <BaseButton @click="adjustingCredit = true">Adjust credit</BaseButton>
          </div>

          <table v-if="ledger && ledger.data.length > 0" class="w-full text-sm">
            <thead class="border-b border-border text-left text-xs text-ink-faint">
              <tr>
                <th class="px-5 py-2 font-medium">Date</th>
                <th class="px-5 py-2 font-medium">Reason</th>
                <th class="px-5 py-2 text-right font-medium">Amount</th>
                <th class="px-5 py-2 text-right font-medium">Balance</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="entry in ledger.data"
                :key="entry.id"
                class="border-b border-border last:border-b-0"
              >
                <td class="px-5 py-2 text-ink-muted">{{ formatDate(entry.occurred_at) }}</td>
                <td class="px-5 py-2">
                  {{ humanize(entry.reason) }}
                  <p v-if="entry.note" class="text-xs text-ink-faint">{{ entry.note }}</p>
                </td>
                <td
                  class="px-5 py-2 text-right tabular-nums"
                  :class="entry.amount_cents > 0 ? 'text-status-active' : 'text-ink'"
                >
                  {{ entry.amount_cents > 0 ? '+' : '' }}{{ formatMoney(entry.amount_cents) }}
                </td>
                <td class="px-5 py-2 text-right text-ink-muted tabular-nums">
                  {{ formatMoney(entry.balance_after_cents) }}
                </td>
              </tr>
            </tbody>
          </table>
          <EmptyState
            v-else-if="ledger"
            title="No credit movements"
            description="Downgrades, refunds to balance and manual adjustments show up here."
          />
          <div v-if="ledger" class="px-5 py-3">
            <PaginationNav :meta="ledger.meta" noun="entries" @change="ledgerPage = $event" />
          </div>
        </section>
      </div>

      <section class="rounded-lg border border-border bg-surface">
        <div class="flex items-center justify-between border-b border-border px-5 py-3">
          <h3 class="text-sm font-semibold">Subscriptions</h3>
          <BaseButton v-if="!hasLiveSubscription" @click="subscribing = true"
            >New subscription</BaseButton
          >
        </div>
        <ul v-if="customer.subscriptions.length > 0">
          <li
            v-for="subscription in customer.subscriptions"
            :key="subscription.id"
            class="flex flex-wrap items-center gap-3 border-b border-border px-5 py-3 last:border-b-0"
          >
            <RouterLink
              :to="{ name: 'subscription', params: { id: subscription.id } }"
              class="flex-1 text-sm font-medium hover:text-accent"
            >
              {{ subscription.plan.name }}
            </RouterLink>
            <span v-if="subscription.cancel_at_period_end" class="text-xs text-ink-muted">
              Cancels {{ formatDate(subscription.current_period_end) }}
            </span>
            <StatusBadge :status="subscription.status" />
          </li>
        </ul>
        <EmptyState
          v-else
          title="No subscriptions yet"
          description="Subscribe this studio to a plan to start billing it."
        />
      </section>

      <PaymentMethodDialog
        v-model:open="addingCard"
        :customer-id="customer.id"
        :has-cards="customer.payment_methods.length > 0"
        @attached="customerData.reload"
      />
      <NewSubscriptionDialog
        v-model:open="subscribing"
        :customer="{ id: customer.id, name: customer.name }"
        @created="onSubscribed"
      />
      <CreditAdjustmentDialog
        v-model:open="adjustingCredit"
        :customer-id="customer.id"
        :balance-cents="customer.credit_balance_cents"
        @adjusted="reloadAll"
      />
    </template>
  </div>
</template>
