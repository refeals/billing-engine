<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'

import type { ApiError } from '@/api/client'
import { attachPaymentMethod, type PaymentMethod } from '@/api/customers'
import { fieldErrors, toApiError } from '@/api/errors'
import { fetchTestCards } from '@/api/testCards'
import BaseButton from '@/components/BaseButton.vue'
import BaseDialog from '@/components/BaseDialog.vue'
import FormField from '@/components/FormField.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockStore } from '@/stores/clock'

const open = defineModel<boolean>('open', { required: true })
const props = defineProps<{ customerId: number; hasCards: boolean }>()
const emit = defineEmits<{ attached: [paymentMethod: PaymentMethod] }>()

const clock = useClockStore()
const inputClass = 'rounded-md border border-border bg-surface px-2.5 py-1.5 text-sm'
const months = Array.from({ length: 12 }, (_, index) => index + 1)

const { data: testCards, reload: loadTestCards } = useAsyncData(fetchTestCards)

// Dates follow the simulated clock, so the default expiry is always in the future.
function simulatedYear() {
  return clock.now ? new Date(clock.now).getUTCFullYear() : new Date().getUTCFullYear()
}

const form = reactive({
  token: 'pm_card_visa',
  expMonth: 12,
  expYear: simulatedYear() + 3,
  makeDefault: false,
})
const error = ref<ApiError | null>(null)
const pending = ref(false)
const errors = computed(() => fieldErrors(error.value))

watch(open, (isOpen) => {
  if (!isOpen) return
  if (!testCards.value) loadTestCards()
  Object.assign(form, {
    token: 'pm_card_visa',
    expMonth: 12,
    expYear: simulatedYear() + 3,
    makeDefault: false,
  })
  error.value = null
})

async function submit() {
  pending.value = true
  error.value = null
  try {
    const paymentMethod = await attachPaymentMethod(props.customerId, {
      test_card: form.token,
      exp_month: form.expMonth,
      exp_year: form.expYear,
      default: form.makeDefault,
    })
    emit('attached', paymentMethod)
    open.value = false
  } catch (caught) {
    error.value = toApiError(caught)
  } finally {
    pending.value = false
  }
}
</script>

<template>
  <BaseDialog v-model:open="open" title="Add test card">
    <form class="space-y-4" novalidate @submit.prevent="submit">
      <FormField
        label="Test card"
        hint="Like Stripe test mode: the card decides how the provider answers a charge."
      >
        <select v-model="form.token" :class="inputClass">
          <option v-for="card in testCards?.data ?? []" :key="card.token" :value="card.token">
            {{ card.description }} ({{ card.brand }} ···· {{ card.last4 }})
          </option>
        </select>
      </FormField>

      <div class="grid grid-cols-2 gap-3">
        <FormField label="Expiry month" :error="errors.exp_month">
          <select v-model.number="form.expMonth" :class="inputClass">
            <option v-for="month in months" :key="month" :value="month">
              {{ String(month).padStart(2, '0') }}
            </option>
          </select>
        </FormField>
        <FormField label="Expiry year" :error="errors.exp_year">
          <input v-model.number="form.expYear" :class="inputClass" type="number" step="1" />
        </FormField>
      </div>

      <label v-if="hasCards" class="flex items-center gap-2 text-sm text-ink-muted">
        <input v-model="form.makeDefault" type="checkbox" />
        Make this the default card
      </label>
      <p v-else class="text-xs text-ink-faint">The first card becomes the default automatically.</p>

      <p v-if="error && Object.keys(errors).length === 0" class="text-sm text-danger" role="alert">
        {{ error.message }}
      </p>

      <div class="flex justify-end gap-2">
        <BaseButton @click="open = false">Cancel</BaseButton>
        <BaseButton type="submit" variant="primary" :disabled="pending">Add card</BaseButton>
      </div>
    </form>
  </BaseDialog>
</template>
