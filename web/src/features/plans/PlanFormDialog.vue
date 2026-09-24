<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'

import type { ApiError } from '@/api/client'
import { fieldErrors, toApiError } from '@/api/errors'
import { createPlan, type Plan, type PlanInterval } from '@/api/plans'
import BaseButton from '@/components/BaseButton.vue'
import BaseDialog from '@/components/BaseDialog.vue'
import FormField from '@/components/FormField.vue'
import { parseMoneyToCents } from '@/utils/money'

const open = defineModel<boolean>('open', { required: true })
const emit = defineEmits<{ created: [plan: Plan] }>()

const inputClass = 'rounded-md border border-border px-2.5 py-1.5 text-sm'

const form = reactive({
  code: '',
  name: '',
  price: '',
  interval: 'month' as PlanInterval,
  trialDays: '14',
})
const priceError = ref<string | null>(null)
const error = ref<ApiError | null>(null)
const pending = ref(false)
const errors = computed(() => fieldErrors(error.value))

watch(open, (isOpen) => {
  if (!isOpen) return
  Object.assign(form, { code: '', name: '', price: '', interval: 'month', trialDays: '14' })
  priceError.value = null
  error.value = null
})

async function submit() {
  // Dollars become cents here, at the API boundary, and nowhere else.
  const amountCents = parseMoneyToCents(form.price)
  priceError.value = amountCents === null ? 'Enter an amount like 49 or 49.90' : null
  if (amountCents === null) return

  pending.value = true
  error.value = null
  try {
    const plan = await createPlan({
      code: form.code.trim(),
      name: form.name.trim(),
      amount_cents: amountCents,
      interval: form.interval,
      trial_days: Number(form.trialDays),
    })
    emit('created', plan)
    open.value = false
  } catch (caught) {
    error.value = toApiError(caught)
  } finally {
    pending.value = false
  }
}
</script>

<template>
  <BaseDialog v-model:open="open" title="New plan">
    <form class="space-y-4" novalidate @submit.prevent="submit">
      <FormField label="Name" :error="errors.name">
        <input v-model="form.name" :class="inputClass" placeholder="Studio Pro" required />
      </FormField>

      <FormField label="Code" :error="errors.code" hint="Lowercase letters, digits and _">
        <input v-model="form.code" :class="`${inputClass} font-mono`" placeholder="studio_pro" />
      </FormField>

      <div class="grid grid-cols-2 gap-3">
        <FormField label="Price (USD)" :error="priceError ?? errors.amount_cents">
          <input v-model="form.price" :class="inputClass" inputmode="decimal" placeholder="49.00" />
        </FormField>

        <FormField label="Billed every" :error="errors.interval">
          <select v-model="form.interval" :class="`${inputClass} bg-surface`">
            <option value="month">Month</option>
            <option value="year">Year</option>
          </select>
        </FormField>
      </div>

      <FormField label="Trial days" :error="errors.trial_days" hint="0 for no trial">
        <input v-model="form.trialDays" :class="inputClass" type="number" min="0" step="1" />
      </FormField>

      <p class="text-xs text-ink-faint">
        Price and interval can't be changed later. To reprice, create a new plan and archive this
        one; current subscribers keep what they signed up for.
      </p>

      <p v-if="error && Object.keys(errors).length === 0" class="text-sm text-danger" role="alert">
        {{ error.message }}
      </p>

      <div class="flex justify-end gap-2">
        <BaseButton @click="open = false">Cancel</BaseButton>
        <BaseButton type="submit" variant="primary" :disabled="pending">Create plan</BaseButton>
      </div>
    </form>
  </BaseDialog>
</template>
