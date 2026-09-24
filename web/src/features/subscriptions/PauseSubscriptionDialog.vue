<script setup lang="ts">
import { ref, watch } from 'vue'

import BaseButton from '@/components/BaseButton.vue'
import BaseDialog from '@/components/BaseDialog.vue'
import FormField from '@/components/FormField.vue'

const open = defineModel<boolean>('open', { required: true })
defineProps<{ pending: boolean; error: string | null; minDate: string }>()
const emit = defineEmits<{ confirm: [resumesAt: string | null] }>()

const resumesAt = ref('')

watch(open, (isOpen) => {
  if (isOpen) resumesAt.value = ''
})
</script>

<template>
  <BaseDialog v-model:open="open" title="Pause subscription">
    <div class="space-y-4 text-sm">
      <p class="text-ink-muted">
        A paused subscription is not billed. Leave the date empty to pause until someone resumes it.
      </p>
      <FormField
        label="Resume on (optional)"
        hint="Resumes automatically at the start of this day (UTC)."
      >
        <input
          v-model="resumesAt"
          type="date"
          :min="minDate"
          class="rounded-md border border-border bg-surface px-2.5 py-1.5 text-sm"
        />
      </FormField>

      <p v-if="error" class="text-danger" role="alert">{{ error }}</p>

      <div class="flex justify-end gap-2">
        <BaseButton @click="open = false">Cancel</BaseButton>
        <BaseButton
          variant="primary"
          :disabled="pending"
          @click="emit('confirm', resumesAt || null)"
        >
          Pause subscription
        </BaseButton>
      </div>
    </div>
  </BaseDialog>
</template>
