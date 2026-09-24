<script setup lang="ts">
import { computed, ref, watch } from 'vue'

import type { Subscription } from '@/api/subscriptions'
import BaseButton from '@/components/BaseButton.vue'
import BaseDialog from '@/components/BaseDialog.vue'
import { formatDate } from '@/utils/format'

const open = defineModel<boolean>('open', { required: true })
const props = defineProps<{ subscription: Subscription; pending: boolean; error: string | null }>()
const emit = defineEmits<{ confirm: [atPeriodEnd: boolean] }>()

const canSchedule = computed(() =>
  props.subscription.allowed_actions.includes('cancel_at_period_end'),
)
const atPeriodEnd = ref(true)

watch(open, (isOpen) => {
  if (isOpen) atPeriodEnd.value = canSchedule.value
})
</script>

<template>
  <BaseDialog v-model:open="open" title="Cancel subscription">
    <div class="space-y-4 text-sm">
      <fieldset class="space-y-3">
        <legend class="sr-only">When</legend>
        <label v-if="canSchedule" class="flex gap-3">
          <input v-model="atPeriodEnd" type="radio" :value="true" class="mt-1" />
          <span>
            <span class="font-medium">At the end of the period</span>
            <span class="block text-ink-muted">
              Stays {{ subscription.status }} until
              {{ formatDate(subscription.current_period_end) }}, then cancels. Can be undone until
              then.
            </span>
          </span>
        </label>
        <label class="flex gap-3">
          <input v-model="atPeriodEnd" type="radio" :value="false" class="mt-1" />
          <span>
            <span class="font-medium">Immediately</span>
            <span class="block text-ink-muted">Access ends now. This can't be undone.</span>
          </span>
        </label>
      </fieldset>

      <p v-if="error" class="text-danger" role="alert">{{ error }}</p>

      <div class="flex justify-end gap-2">
        <BaseButton @click="open = false">Keep subscription</BaseButton>
        <BaseButton variant="danger" :disabled="pending" @click="emit('confirm', atPeriodEnd)">
          {{ atPeriodEnd ? 'Schedule cancellation' : 'Cancel now' }}
        </BaseButton>
      </div>
    </div>
  </BaseDialog>
</template>
