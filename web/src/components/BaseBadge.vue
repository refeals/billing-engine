<script setup lang="ts">
withDefaults(defineProps<{ tone?: 'neutral' | 'success' | 'warning' | 'danger' | 'accent' }>(), {
  tone: 'neutral',
})

const tones = {
  neutral: 'bg-canvas text-ink-muted',
  success: 'bg-status-active/10 text-status-active',
  warning: 'bg-status-past-due/10 text-status-past-due',
  danger: 'bg-danger/10 text-danger',
  accent: 'bg-accent/10 text-accent',
}
</script>

<template>
  <span
    class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium"
    :class="tones[tone]"
  >
    <slot />
  </span>
</template>
