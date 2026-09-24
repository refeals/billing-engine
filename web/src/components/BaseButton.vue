<script setup lang="ts">
withDefaults(
  defineProps<{
    variant?: 'primary' | 'secondary' | 'danger' | 'ghost'
    type?: 'button' | 'submit'
    disabled?: boolean
  }>(),
  { variant: 'secondary', type: 'button', disabled: false },
)

const variants = {
  primary: 'bg-accent text-white hover:bg-accent-strong border-transparent',
  secondary: 'bg-surface text-ink hover:bg-canvas border-border',
  danger: 'bg-surface text-danger hover:bg-danger/5 border-border',
  ghost: 'bg-transparent text-accent hover:text-accent-strong border-transparent',
}
</script>

<template>
  <button
    :type="type"
    :disabled="disabled"
    class="inline-flex items-center justify-center gap-1.5 rounded-md border px-3 py-1.5 text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50"
    :class="variants[variant]"
  >
    <slot />
  </button>
</template>
