<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'

import type { ApiError } from '@/api/client'
import { createCustomer, type CustomerDetail } from '@/api/customers'
import { fieldErrors, toApiError } from '@/api/errors'
import BaseButton from '@/components/BaseButton.vue'
import BaseDialog from '@/components/BaseDialog.vue'
import FormField from '@/components/FormField.vue'

const open = defineModel<boolean>('open', { required: true })
const emit = defineEmits<{ created: [customer: CustomerDetail] }>()

const inputClass = 'rounded-md border border-border px-2.5 py-1.5 text-sm'
const form = reactive({ name: '', email: '' })
const error = ref<ApiError | null>(null)
const pending = ref(false)
const errors = computed(() => fieldErrors(error.value))

watch(open, (isOpen) => {
  if (!isOpen) return
  Object.assign(form, { name: '', email: '' })
  error.value = null
})

async function submit() {
  pending.value = true
  error.value = null
  try {
    const customer = await createCustomer({ name: form.name.trim(), email: form.email.trim() })
    emit('created', customer)
    open.value = false
  } catch (caught) {
    error.value = toApiError(caught)
  } finally {
    pending.value = false
  }
}
</script>

<template>
  <BaseDialog v-model:open="open" title="New customer">
    <form class="space-y-4" novalidate @submit.prevent="submit">
      <FormField label="Studio name" :error="errors.name">
        <input v-model="form.name" :class="inputClass" placeholder="Studio Flow" />
      </FormField>

      <FormField label="Billing email" :error="errors.email">
        <input
          v-model="form.email"
          :class="inputClass"
          type="email"
          placeholder="owner@studio.test"
        />
      </FormField>

      <p v-if="error && Object.keys(errors).length === 0" class="text-sm text-danger" role="alert">
        {{ error.message }}
      </p>

      <div class="flex justify-end gap-2">
        <BaseButton @click="open = false">Cancel</BaseButton>
        <BaseButton type="submit" variant="primary" :disabled="pending">Create customer</BaseButton>
      </div>
    </form>
  </BaseDialog>
</template>
