<script setup lang="ts">
import BaseButton from '@/components/BaseButton.vue'
import BaseDialog from '@/components/BaseDialog.vue'

const open = defineModel<boolean>('open', { required: true })
withDefaults(
  defineProps<{
    title: string
    confirmLabel: string
    pending?: boolean
    error?: string | null
    variant?: 'primary' | 'danger'
  }>(),
  { pending: false, error: null, variant: 'danger' },
)
defineEmits<{ confirm: [] }>()
</script>

<template>
  <BaseDialog v-model:open="open" :title="title">
    <div class="space-y-4 text-sm text-ink-muted">
      <slot />
      <p v-if="error" class="text-danger" role="alert">{{ error }}</p>
      <div class="flex justify-end gap-2">
        <BaseButton @click="open = false">Cancel</BaseButton>
        <BaseButton :variant="variant" :disabled="pending" @click="$emit('confirm')">
          {{ confirmLabel }}
        </BaseButton>
      </div>
    </div>
  </BaseDialog>
</template>
