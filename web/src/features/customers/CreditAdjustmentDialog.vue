<script setup lang="ts">
import { reactive, ref, watch } from 'vue'

import type { ApiError } from '@/api/client'
import { adjustCredit, type CreditLedgerEntry } from '@/api/customers'
import { toApiError } from '@/api/errors'
import BaseButton from '@/components/BaseButton.vue'
import BaseDialog from '@/components/BaseDialog.vue'
import FormField from '@/components/FormField.vue'
import { formatMoney } from '@/utils/format'
import { parseMoneyToCents } from '@/utils/money'

const open = defineModel<boolean>('open', { required: true })
const props = defineProps<{ customerId: number; balanceCents: number }>()
const emit = defineEmits<{ adjusted: [entry: CreditLedgerEntry] }>()

const inputClass = 'rounded-md border border-border bg-surface px-2.5 py-1.5 text-sm'
const form = reactive({ direction: 'add' as 'add' | 'remove', amount: '', note: '' })
const localError = ref<string | null>(null)
const error = ref<ApiError | null>(null)
const pending = ref(false)

watch(open, (isOpen) => {
  if (!isOpen) return
  Object.assign(form, { direction: 'add', amount: '', note: '' })
  localError.value = null
  error.value = null
})

function describeError(apiError: ApiError): string {
  if (apiError.code !== 'insufficient_credit') return apiError.message

  const balance = Number(apiError.details.balance_cents ?? 0)
  const requested = Number(apiError.details.requested_cents ?? 0)
  return `Can't remove ${formatMoney(requested)}: the balance is only ${formatMoney(balance)}.`
}

async function submit() {
  const cents = parseMoneyToCents(form.amount)
  localError.value =
    cents === null || cents === 0
      ? 'Enter an amount like 10 or 10.50'
      : form.note.trim() === ''
        ? 'Explain why the balance is being adjusted'
        : null
  if (localError.value || cents === null) return

  pending.value = true
  error.value = null
  try {
    const entry = await adjustCredit(props.customerId, {
      amount_cents: form.direction === 'add' ? cents : -cents,
      note: form.note.trim(),
    })
    emit('adjusted', entry)
    open.value = false
  } catch (caught) {
    error.value = toApiError(caught)
  } finally {
    pending.value = false
  }
}
</script>

<template>
  <BaseDialog v-model:open="open" title="Adjust credit">
    <form class="space-y-4" novalidate @submit.prevent="submit">
      <p class="text-sm text-ink-muted">
        Current balance: <strong class="text-ink">{{ formatMoney(balanceCents) }}</strong>
      </p>

      <fieldset class="flex gap-4 text-sm">
        <legend class="sr-only">Direction</legend>
        <label class="flex items-center gap-2">
          <input v-model="form.direction" type="radio" value="add" /> Add credit
        </label>
        <label class="flex items-center gap-2">
          <input v-model="form.direction" type="radio" value="remove" /> Remove credit
        </label>
      </fieldset>

      <FormField label="Amount (USD)">
        <input v-model="form.amount" :class="inputClass" inputmode="decimal" placeholder="10.00" />
      </FormField>

      <FormField label="Note" hint="Kept in the ledger and the audit log.">
        <input v-model="form.note" :class="inputClass" placeholder="Goodwill credit after outage" />
      </FormField>

      <p v-if="localError || error" class="text-sm text-danger" role="alert">
        {{ localError ?? describeError(error!) }}
      </p>

      <div class="flex justify-end gap-2">
        <BaseButton @click="open = false">Cancel</BaseButton>
        <BaseButton type="submit" variant="primary" :disabled="pending">Save adjustment</BaseButton>
      </div>
    </form>
  </BaseDialog>
</template>
