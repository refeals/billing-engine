<script setup lang="ts">
defineProps<{ title: string; description?: string }>()
</script>

<template>
  <div class="px-4 py-10 text-center">
    <p class="text-sm font-medium text-ink">{{ title }}</p>
    <p v-if="description" class="mt-1 text-sm text-ink-muted">{{ description }}</p>
    <div v-if="$slots.default" class="mt-4 flex justify-center"><slot /></div>
  </div>
</template>
