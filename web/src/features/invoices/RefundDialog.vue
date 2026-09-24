<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'

import type { ApiError } from '@/api/client'
import { toApiError } from '@/api/errors'
import { keyAfterFailure, newIdempotencyKey } from '@/api/idempotency'
import type { InvoiceDetail } from '@/api/invoices'
import {
  createRefund,
  REFUND_REASONS,
  refundAmountError,
  type RefundDestination,
  type RefundReason,
} from '@/api/refunds'
import BaseButton from '@/components/BaseButton.vue'
import BaseDialog from '@/components/BaseDialog.vue'
import FormField from '@/components/FormField.vue'
import { formatMoney } from '@/utils/format'
import { parseMoneyToCents } from '@/utils/money'
import { humanize } from '@/utils/text'

const open = defineModel<boolean>('open', { required: true })
const props = defineProps<{ invoice: InvoiceDetail }>()
const emit = defineEmits<{ refunded: [invoice: InvoiceDetail] }>()

const inputClass = 'rounded-md border border-border bg-surface px-2.5 py-1.5 text-sm'
const hasCardCharge = computed(() =>
  props.invoice.payment_attempts.some((attempt) => attempt.status === 'succeeded'),
)

const form = reactive({
  amount: '',
  destination: 'original_method' as RefundDestination,
  reason: 'requested_by_customer' as RefundReason,
})
const localError = ref<string | null>(null)
const error = ref<ApiError | null>(null)
const pending = ref(false)
let idempotencyKey = newIdempotencyKey()

watch(open, (isOpen) => {
  if (!isOpen) return
  idempotencyKey = newIdempotencyKey()
  // Prefilled with everything that can still be refunded: the common case is a full refund.
  Object.assign(form, {
    amount: (props.invoice.refundable_cents / 100).toFixed(2),
    destination: hasCardCharge.value ? 'original_method' : 'credit_balance',
    reason: 'requested_by_customer',
  })
  localError.value = null
  error.value = null
})

async function submit() {
  const cents = parseMoneyToCents(form.amount)
  localError.value = refundAmountError(cents, props.invoice.refundable_cents)
  if (localError.value || cents === null) return

  pending.value = true
  error.value = null
  try {
    const invoice = await createRefund(
      props.invoice.id,
      { amount_cents: cents, destination: form.destination, reason: form.reason },
      idempotencyKey,
    )
    emit('refunded', invoice)
    open.value = false
  } catch (caught) {
    error.value = toApiError(caught)
    idempotencyKey = keyAfterFailure(idempotencyKey, error.value)
  } finally {
    pending.value = false
  }
}
</script>

<template>
  <BaseDialog v-model:open="open" title="Refund">
    <form class="space-y-4 text-sm" novalidate @submit.prevent="submit">
      <p class="text-ink-muted">
        Up to <strong class="text-ink">{{ formatMoney(invoice.refundable_cents) }}</strong> can
        still be refunded on {{ invoice.number }}.
      </p>

      <FormField label="Amount (USD)" :error="localError ?? undefined">
        <input v-model="form.amount" :class="inputClass" inputmode="decimal" />
      </FormField>

      <fieldset class="space-y-2">
        <legend class="mb-1 font-medium">Refund to</legend>
        <label class="flex items-center gap-2" :class="hasCardCharge ? '' : 'text-ink-faint'">
          <input
            v-model="form.destination"
            type="radio"
            value="original_method"
            :disabled="!hasCardCharge"
          />
          The card that paid (through the payment provider)
        </label>
        <label class="flex items-center gap-2">
          <input v-model="form.destination" type="radio" value="credit_balance" />
          Credit balance (spent by the next invoices)
        </label>
      </fieldset>

      <FormField label="Reason">
        <select v-model="form.reason" :class="inputClass">
          <option v-for="reason in REFUND_REASONS" :key="reason" :value="reason">
            {{ humanize(reason) }}
          </option>
        </select>
      </FormField>

      <p v-if="error" class="text-danger" role="alert">{{ error.message }}</p>

      <div class="flex justify-end gap-2">
        <BaseButton @click="open = false">Cancel</BaseButton>
        <BaseButton type="submit" variant="danger" :disabled="pending">Refund</BaseButton>
      </div>
    </form>
  </BaseDialog>
</template>
