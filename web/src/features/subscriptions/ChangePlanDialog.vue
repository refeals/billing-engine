<script setup lang="ts">
import { computed, ref, watch } from 'vue'

import type { ApiError } from '@/api/client'
import { toApiError } from '@/api/errors'
import { keyAfterFailure, newIdempotencyKey } from '@/api/idempotency'
import {
  applyPlanChange,
  previewPlanChange,
  type PlanChange,
  type PlanChangeQuote,
  type PlanChangeStrategy,
} from '@/api/planChanges'
import { fetchPlans } from '@/api/plans'
import type { Subscription } from '@/api/subscriptions'
import BaseButton from '@/components/BaseButton.vue'
import BaseDialog from '@/components/BaseDialog.vue'
import FormField from '@/components/FormField.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { formatDate, formatMoney } from '@/utils/format'

const open = defineModel<boolean>('open', { required: true })
const props = defineProps<{ subscription: Subscription }>()
const emit = defineEmits<{ changed: [planChange: PlanChange]; conflict: [] }>()

const inputClass = 'rounded-md border border-border bg-surface px-2.5 py-1.5 text-sm'

const plans = useAsyncData(() => fetchPlans())
// Proration only works between plans billed on the same interval.
const candidates = computed(() =>
  (plans.data.value?.data ?? []).filter(
    (plan) =>
      plan.id !== props.subscription.plan.id && plan.interval === props.subscription.plan.interval,
  ),
)

const planId = ref<number | null>(null)
const strategy = ref<PlanChangeStrategy>('immediate')
const quote = ref<PlanChangeQuote | null>(null)
const quoteError = ref<string | null>(null)
const applyError = ref<ApiError | null>(null)
const pending = ref(false)
let idempotencyKey = newIdempotencyKey()
let latestPreview = 0

watch(open, (isOpen) => {
  if (!isOpen) return
  idempotencyKey = newIdempotencyKey()
  planId.value = null
  strategy.value = 'immediate'
  quote.value = null
  quoteError.value = null
  applyError.value = null
  plans.reload()
})

// Every choice is re-quoted by the API, so the numbers shown are the server's, not a guess.
async function refreshPreview() {
  // Drop the previous quote at once: until the new one arrives, confirming must not apply a
  // quote for a plan or strategy that is no longer selected.
  quote.value = null
  if (planId.value === null) return
  const request = ++latestPreview
  quoteError.value = null
  try {
    const result = await previewPlanChange(props.subscription.id, {
      plan_id: planId.value,
      strategy: strategy.value,
    })
    if (request === latestPreview) quote.value = result
  } catch (caught) {
    if (request !== latestPreview) return
    const error = toApiError(caught)
    // The kind of change decides the strategies; fall back to one that is allowed.
    const allowed = error.details.allowed
    if (error.code === 'strategy_not_allowed' && Array.isArray(allowed) && allowed.length > 0) {
      strategy.value = allowed[0] as PlanChangeStrategy
      return
    }
    quote.value = null
    quoteError.value = error.message
  }
}

watch([planId, strategy], refreshPreview)

const strategyLabels: Record<PlanChangeStrategy, string> = {
  immediate: 'Now',
  at_period_end: 'At the end of the period',
}

// Only a quote for exactly what is selected can be confirmed.
const confirmable = computed(
  () =>
    quote.value !== null &&
    quote.value.to_plan.id === planId.value &&
    quote.value.strategy === strategy.value,
)

async function confirm() {
  if (!quote.value || !confirmable.value) return
  pending.value = true
  applyError.value = null
  try {
    const planChange = await applyPlanChange(props.subscription, quote.value, idempotencyKey)
    emit('changed', planChange)
    open.value = false
  } catch (caught) {
    applyError.value = toApiError(caught)
    idempotencyKey = keyAfterFailure(idempotencyKey, applyError.value)
    if (applyError.value.isConflict) {
      emit('conflict')
      open.value = false
    }
  } finally {
    pending.value = false
  }
}

const summary = computed(() => {
  const current = quote.value
  if (!current) return null
  if (current.kind === 'trial_swap')
    return 'Still in trial: the plan changes now and nothing is charged.'
  if (current.strategy === 'at_period_end') {
    return `Switches at the next renewal, on ${formatDate(current.effective_at)}. Nothing is charged now.`
  }
  if (current.kind === 'upgrade')
    return `Charged now: ${formatMoney(current.amount_due_now_cents)}.`
  if (current.credit_to_balance_cents > 0) {
    return `${formatMoney(current.credit_to_balance_cents)} of unused time becomes credit for the next invoices.`
  }
  return 'Same price: the plan changes now and nothing is charged.'
})
</script>

<template>
  <BaseDialog v-model:open="open" title="Change plan">
    <div class="space-y-4 text-sm">
      <FormField label="New plan" :hint="`Currently on ${subscription.plan.name}.`">
        <select v-model="planId" :class="inputClass">
          <option :value="null" disabled>Select a plan</option>
          <option v-for="plan in candidates" :key="plan.id" :value="plan.id">
            {{ plan.name }} · {{ formatMoney(plan.amount_cents) }} / {{ plan.interval }}
          </option>
        </select>
      </FormField>

      <fieldset v-if="quote && quote.allowed_strategies.length > 1" class="space-y-2">
        <legend class="mb-1 font-medium">When</legend>
        <label
          v-for="option in quote.allowed_strategies"
          :key="option"
          class="flex items-center gap-2"
        >
          <input v-model="strategy" type="radio" :value="option" />
          {{ strategyLabels[option] }}
        </label>
      </fieldset>

      <p v-if="quoteError" class="text-danger" role="alert">{{ quoteError }}</p>

      <div v-if="quote" class="space-y-2 rounded-md bg-canvas p-3">
        <table v-if="quote.lines.length > 0" class="w-full">
          <tbody>
            <tr v-for="line in quote.lines" :key="line.kind">
              <td class="py-0.5 text-ink-muted">{{ line.description }}</td>
              <td class="py-0.5 text-right tabular-nums">{{ formatMoney(line.amount_cents) }}</td>
            </tr>
            <tr v-if="quote.credit_applied_cents > 0">
              <td class="py-0.5 text-ink-muted">Credit balance applied</td>
              <td class="py-0.5 text-right tabular-nums">
                {{ formatMoney(-quote.credit_applied_cents) }}
              </td>
            </tr>
            <tr class="font-semibold">
              <td class="pt-1">Net</td>
              <td class="pt-1 text-right tabular-nums">{{ formatMoney(quote.net_cents) }}</td>
            </tr>
          </tbody>
        </table>
        <p>{{ summary }}</p>
        <p v-if="quote.remaining_ratio" class="text-xs text-ink-faint">
          Prorated for {{ (Number(quote.remaining_ratio) * 100).toFixed(1) }}% of the period left.
        </p>
      </div>

      <p v-if="applyError && !applyError.isConflict" class="text-danger" role="alert">
        {{ applyError.message }}
      </p>

      <div class="flex justify-end gap-2">
        <BaseButton @click="open = false">Cancel</BaseButton>
        <BaseButton variant="primary" :disabled="pending || !confirmable" @click="confirm">
          Confirm change
        </BaseButton>
      </div>
    </div>
  </BaseDialog>
</template>
