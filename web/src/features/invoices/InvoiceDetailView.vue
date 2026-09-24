<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute } from 'vue-router'

import { toApiError } from '@/api/errors'
import { keyAfterFailure, newIdempotencyKey } from '@/api/idempotency'
import { fetchInvoice, retryInvoicePayment } from '@/api/invoices'
import BaseBadge from '@/components/BaseBadge.vue'
import BaseButton from '@/components/BaseButton.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import EmptyState from '@/components/EmptyState.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockRefresh } from '@/composables/useClockRefresh'
import { formatDate, formatDateTime, formatMoney } from '@/utils/format'
import { humanize } from '@/utils/text'
import InvoiceStatusBadge from './InvoiceStatusBadge.vue'
import RefundDialog from './RefundDialog.vue'

const route = useRoute()
const invoiceId = computed(() => String(route.params.id))

const { data: invoice, error, reload } = useAsyncData(() => fetchInvoice(invoiceId.value))
useClockRefresh(reload)
watch(invoiceId, reload)

const confirming = ref(false)
const pending = ref(false)
const retryError = ref<string | null>(null)
let idempotencyKey = newIdempotencyKey()

function openRetry() {
  idempotencyKey = newIdempotencyKey()
  retryError.value = null
  confirming.value = true
}

async function retry() {
  if (!invoice.value) return
  pending.value = true
  retryError.value = null
  try {
    invoice.value = await retryInvoicePayment(invoice.value.id, idempotencyKey)
    confirming.value = false
  } catch (caught) {
    const apiError = toApiError(caught)
    idempotencyKey = keyAfterFailure(idempotencyKey, apiError)
    retryError.value = apiError.message
  } finally {
    pending.value = false
  }
}

const refunding = ref(false)

const totals = computed(() => {
  const current = invoice.value
  if (!current) return []
  return [
    { label: 'Subtotal', cents: current.subtotal_cents },
    {
      label: 'Credit applied',
      cents: -current.credit_applied_cents,
      hidden: current.credit_applied_cents === 0,
    },
    { label: 'Total', cents: current.total_cents, strong: true },
    { label: 'Paid', cents: current.amount_paid_cents },
    {
      label: 'Refunded',
      cents: -current.amount_refunded_cents,
      hidden: current.amount_refunded_cents === 0,
    },
    { label: 'Amount due', cents: current.amount_due_cents, strong: true },
    {
      label: 'Still refundable',
      cents: current.refundable_cents,
      hidden: current.status !== 'paid',
    },
  ].filter((row) => !row.hidden)
})
</script>

<template>
  <div class="space-y-6">
    <RouterLink to="/invoices" class="text-sm text-accent hover:text-accent-strong">
      ← All invoices
    </RouterLink>

    <p v-if="error" class="text-sm text-danger" role="alert">{{ error.message }}</p>

    <template v-if="invoice">
      <header class="rounded-lg border border-border bg-surface p-5">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div class="flex items-center gap-3">
              <h2 class="font-mono text-lg font-semibold">{{ invoice.number }}</h2>
              <InvoiceStatusBadge :status="invoice.status" />
            </div>
            <p class="text-sm text-ink-muted">
              <RouterLink
                :to="{ name: 'customer', params: { id: invoice.customer.id } }"
                class="text-accent hover:text-accent-strong"
              >
                {{ invoice.customer.name }}
              </RouterLink>
              ·
              <RouterLink
                :to="{ name: 'subscription', params: { id: invoice.subscription_id } }"
                class="text-accent hover:text-accent-strong"
              >
                Subscription #{{ invoice.subscription_id }}
              </RouterLink>
              · {{ humanize(invoice.billing_reason) }}
            </p>
            <p class="mt-2 font-mono text-xs text-ink-faint">
              {{ invoice.provider_invoice_id }} · issued {{ formatDateTime(invoice.issued_at) }}
            </p>
          </div>
          <div class="flex gap-2">
            <BaseButton v-if="invoice.payable" variant="primary" @click="openRetry">
              Retry payment
            </BaseButton>
            <BaseButton
              v-if="invoice.refundable_cents > 0"
              variant="danger"
              @click="refunding = true"
            >
              Refund
            </BaseButton>
          </div>
        </div>
      </header>

      <div class="grid gap-6 lg:grid-cols-3">
        <section class="rounded-lg border border-border bg-surface lg:col-span-2">
          <h3 class="border-b border-border px-5 py-3 text-sm font-semibold">
            {{ formatDate(invoice.period_start) }} – {{ formatDate(invoice.period_end) }}
          </h3>
          <table class="w-full text-sm">
            <tbody>
              <tr
                v-for="line in invoice.line_items"
                :key="line.id"
                class="border-b border-border last:border-b-0"
                :class="line.amount_cents < 0 ? 'bg-status-active/5' : ''"
              >
                <td class="px-5 py-3">
                  {{ line.description }}
                  <BaseBadge v-if="line.kind !== 'subscription'" class="ml-2">
                    {{ humanize(line.kind) }}
                  </BaseBadge>
                </td>
                <td class="px-5 py-3 text-right tabular-nums">
                  {{ formatMoney(line.amount_cents) }}
                </td>
              </tr>
            </tbody>
          </table>
        </section>

        <section class="rounded-lg border border-border bg-surface p-5">
          <dl class="space-y-2 text-sm">
            <div
              v-for="row in totals"
              :key="row.label"
              class="flex justify-between"
              :class="row.strong ? 'font-semibold' : 'text-ink-muted'"
            >
              <dt>{{ row.label }}</dt>
              <dd class="tabular-nums">{{ formatMoney(row.cents) }}</dd>
            </div>
          </dl>
        </section>
      </div>

      <section class="rounded-lg border border-border bg-surface">
        <h3 class="border-b border-border px-5 py-3 text-sm font-semibold">Payment attempts</h3>
        <table v-if="invoice.payment_attempts.length > 0" class="w-full text-sm">
          <thead class="border-b border-border text-left text-xs text-ink-faint">
            <tr>
              <th class="px-5 py-2 font-medium">When</th>
              <th class="px-5 py-2 font-medium">Card</th>
              <th class="px-5 py-2 text-right font-medium">Amount</th>
              <th class="px-5 py-2 font-medium">Result</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="attempt in invoice.payment_attempts"
              :key="attempt.id"
              class="border-b border-border last:border-b-0"
            >
              <td class="px-5 py-2 text-ink-muted">{{ formatDateTime(attempt.attempted_at) }}</td>
              <td class="px-5 py-2">
                {{
                  attempt.card
                    ? `${humanize(attempt.card.brand)} ···· ${attempt.card.last4}`
                    : 'No card'
                }}
              </td>
              <td class="px-5 py-2 text-right tabular-nums">
                {{ formatMoney(attempt.amount_cents) }}
              </td>
              <td class="px-5 py-2">
                <BaseBadge :tone="attempt.status === 'succeeded' ? 'success' : 'danger'">
                  {{
                    attempt.status === 'succeeded'
                      ? 'Succeeded'
                      : humanize(attempt.failure_code ?? 'failed')
                  }}
                </BaseBadge>
              </td>
            </tr>
          </tbody>
        </table>
        <EmptyState
          v-else
          title="No charges"
          description="Nothing was charged: the invoice is still waiting, or credit covered it."
        />
      </section>

      <section v-if="invoice.refunds.length > 0" class="rounded-lg border border-border bg-surface">
        <h3 class="border-b border-border px-5 py-3 text-sm font-semibold">Refunds</h3>
        <table class="w-full text-sm">
          <tbody>
            <tr
              v-for="refund in invoice.refunds"
              :key="refund.id"
              class="border-b border-border last:border-b-0"
            >
              <td class="px-5 py-2 text-ink-muted">{{ formatDateTime(refund.requested_at) }}</td>
              <td class="px-5 py-2">
                {{ refund.destination === 'credit_balance' ? 'To credit balance' : 'To card' }}
                <p class="text-xs text-ink-faint">{{ humanize(refund.reason) }}</p>
              </td>
              <td class="px-5 py-2 text-right tabular-nums">
                {{ formatMoney(refund.amount_cents) }}
              </td>
              <td class="px-5 py-2 text-right">
                <BaseBadge
                  :tone="
                    refund.status === 'succeeded'
                      ? 'success'
                      : refund.status === 'failed'
                        ? 'danger'
                        : 'warning'
                  "
                  :title="refund.failure_reason ?? undefined"
                >
                  {{
                    refund.status === 'failed' && refund.failure_reason
                      ? humanize(refund.failure_reason)
                      : humanize(refund.status)
                  }}
                </BaseBadge>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <RefundDialog
        v-model:open="refunding"
        :invoice="invoice"
        @refunded="(updated) => (invoice = updated)"
      />

      <ConfirmDialog
        v-model:open="confirming"
        title="Retry payment"
        confirm-label="Charge now"
        variant="primary"
        :pending="pending"
        :error="retryError"
        @confirm="retry"
      >
        <p>
          Charges {{ formatMoney(invoice.amount_due_cents) }} to the customer's current default
          card. The result comes back from the payment provider.
        </p>
      </ConfirmDialog>
    </template>
  </div>
</template>
