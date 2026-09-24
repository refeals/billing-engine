<script setup lang="ts">
defineProps<{ label: string; error?: string; hint?: string }>()
</script>

<template>
  <label class="flex flex-col gap-1 text-sm">
    <span class="font-medium text-ink">{{ label }}</span>
    <slot />
    <span v-if="error" class="text-xs text-danger">{{ error }}</span>
    <span v-else-if="hint" class="text-xs text-ink-faint">{{ hint }}</span>
  </label>
</template>
