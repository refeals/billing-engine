<script setup lang="ts">
import { reactive, ref } from 'vue'

import { toApiError } from '@/api/errors'
import {
  emitProviderEvent,
  MANUAL_EVENT_TYPES,
  type ManualEventType,
  type ProviderEvent,
} from '@/api/simulatorEvents'
import {
  fetchSubscriptions,
  SUBSCRIPTION_STATUSES,
  type SubscriptionStatus,
} from '@/api/subscriptions'
import BaseButton from '@/components/BaseButton.vue'
import FormField from '@/components/FormField.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockRefresh } from '@/composables/useClockRefresh'
import { humanize } from '@/utils/text'

const emit = defineEmits<{ emitted: [event: ProviderEvent] }>()

const inputClass = 'rounded-md border border-border bg-surface px-2.5 py-1.5 text-sm'

const subscriptions = useAsyncData(() => fetchSubscriptions())
useClockRefresh(subscriptions.reload)

const form = reactive({
  subscriptionId: null as number | null,
  type: 'customer.subscription.updated' as ManualEventType,
  status: '' as SubscriptionStatus | '',
  delivery: 'deliver' as 'deliver' | 'drop',
  copies: 1,
})
const pending = ref(false)
const error = ref<string | null>(null)

async function submit() {
  if (form.subscriptionId === null) return
  pending.value = true
  error.value = null
  try {
    const event = await emitProviderEvent({
      subscription_id: form.subscriptionId,
      type: form.type,
      status: form.status || undefined,
      delivery: form.delivery,
      copies: form.copies,
    })
    emit('emitted', event)
  } catch (caught) {
    error.value = toApiError(caught).message
  } finally {
    pending.value = false
  }
}
</script>

<template>
  <form
    class="space-y-4 rounded-lg border border-border bg-surface p-5"
    novalidate
    @submit.prevent="submit"
  >
    <div>
      <h2 class="text-sm font-semibold">Make the provider report a subscription</h2>
      <p class="mt-1 text-sm text-ink-muted">
        The fake Stripe sends a webhook through its outbox, like the real one. Drop it to simulate a
        lost webhook, or send copies to simulate duplicate deliveries.
      </p>
    </div>

    <div class="grid gap-3 sm:grid-cols-2">
      <FormField label="Subscription">
        <select v-model="form.subscriptionId" :class="inputClass">
          <option :value="null" disabled>Select a subscription</option>
          <option
            v-for="subscription in subscriptions.data.value?.data ?? []"
            :key="subscription.id"
            :value="subscription.id"
          >
            {{ subscription.customer.name }} · {{ subscription.plan.name }} ({{
              humanize(subscription.status)
            }})
          </option>
        </select>
      </FormField>

      <FormField label="Event type">
        <select v-model="form.type" :class="`${inputClass} font-mono`">
          <option v-for="type in MANUAL_EVENT_TYPES" :key="type" :value="type">{{ type }}</option>
        </select>
      </FormField>

      <FormField label="Status the provider reports" hint="Empty: the engine's current status.">
        <select v-model="form.status" :class="inputClass">
          <option value="">Same as the engine</option>
          <option v-for="status in SUBSCRIPTION_STATUSES" :key="status" :value="status">
            {{ humanize(status) }}
          </option>
        </select>
      </FormField>

      <div class="grid grid-cols-2 gap-3">
        <FormField label="Delivery">
          <select v-model="form.delivery" :class="inputClass">
            <option value="deliver">Deliver</option>
            <option value="drop">Drop (lost)</option>
          </select>
        </FormField>
        <FormField label="Copies">
          <input
            v-model.number="form.copies"
            :class="inputClass"
            type="number"
            min="1"
            max="5"
            :disabled="form.delivery === 'drop'"
          />
        </FormField>
      </div>
    </div>

    <p v-if="error" class="text-sm text-danger" role="alert">{{ error }}</p>

    <BaseButton type="submit" variant="primary" :disabled="pending || form.subscriptionId === null">
      Send event
    </BaseButton>
  </form>
</template>
