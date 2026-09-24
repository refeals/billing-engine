<script setup lang="ts">
import { computed, ref, watch } from 'vue'

import type { ApiError } from '@/api/client'
import { fetchCustomers } from '@/api/customers'
import { toApiError } from '@/api/errors'
import { keyAfterFailure, newIdempotencyKey } from '@/api/idempotency'
import { fetchPlans } from '@/api/plans'
import { createSubscription, type Subscription } from '@/api/subscriptions'
import BaseButton from '@/components/BaseButton.vue'
import BaseDialog from '@/components/BaseDialog.vue'
import FormField from '@/components/FormField.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { formatMoney } from '@/utils/format'

const open = defineModel<boolean>('open', { required: true })
const props = defineProps<{ customer?: { id: number; name: string } }>()
const emit = defineEmits<{ created: [subscription: Subscription] }>()

const inputClass = 'rounded-md border border-border bg-surface px-2.5 py-1.5 text-sm'

const customerQuery = ref('')
const customerId = ref<number | null>(null)
const planId = ref<number | null>(null)
const error = ref<ApiError | null>(null)
const pending = ref(false)
let idempotencyKey = newIdempotencyKey()

const customers = useAsyncData(() => fetchCustomers({ q: customerQuery.value }))
const plans = useAsyncData(() => fetchPlans())
const selectedPlan = computed(() => plans.data.value?.data.find((plan) => plan.id === planId.value))

let debounce: ReturnType<typeof setTimeout> | undefined
watch(customerQuery, () => {
  clearTimeout(debounce)
  debounce = setTimeout(customers.reload, 250)
})

watch(open, (isOpen) => {
  if (!isOpen) return
  // A new key per opening: retries of this attempt are deduplicated, a new attempt isn't.
  idempotencyKey = newIdempotencyKey()
  error.value = null
  customerQuery.value = ''
  customerId.value = props.customer?.id ?? null
  planId.value = null
  if (!props.customer) customers.reload()
  plans.reload()
})

async function submit() {
  if (customerId.value === null || planId.value === null) return

  pending.value = true
  error.value = null
  try {
    const subscription = await createSubscription(
      { customer_id: customerId.value, plan_id: planId.value },
      idempotencyKey,
    )
    emit('created', subscription)
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
  <BaseDialog v-model:open="open" title="New subscription">
    <form class="space-y-4" novalidate @submit.prevent="submit">
      <FormField v-if="customer" label="Customer">
        <p class="text-sm">{{ customer.name }}</p>
      </FormField>
      <template v-else>
        <FormField label="Find customer">
          <input
            v-model="customerQuery"
            :class="inputClass"
            type="search"
            placeholder="Name or email"
          />
        </FormField>
        <FormField label="Customer">
          <select v-model="customerId" :class="inputClass" required>
            <option :value="null" disabled>Select a customer</option>
            <option
              v-for="option in customers.data.value?.data ?? []"
              :key="option.id"
              :value="option.id"
            >
              {{ option.name }} ({{ option.email }})
            </option>
          </select>
        </FormField>
      </template>

      <FormField
        label="Plan"
        :hint="
          selectedPlan
            ? selectedPlan.trial_days > 0
              ? `Starts with a ${selectedPlan.trial_days}-day trial.`
              : 'Starts active right away (no trial).'
            : undefined
        "
      >
        <select v-model="planId" :class="inputClass" required>
          <option :value="null" disabled>Select a plan</option>
          <option v-for="plan in plans.data.value?.data ?? []" :key="plan.id" :value="plan.id">
            {{ plan.name }} · {{ formatMoney(plan.amount_cents) }} / {{ plan.interval }}
          </option>
        </select>
      </FormField>

      <p v-if="error" class="text-sm text-danger" role="alert">{{ error.message }}</p>

      <div class="flex justify-end gap-2">
        <BaseButton @click="open = false">Cancel</BaseButton>
        <BaseButton
          type="submit"
          variant="primary"
          :disabled="pending || customerId === null || planId === null"
        >
          Create subscription
        </BaseButton>
      </div>
    </form>
  </BaseDialog>
</template>
