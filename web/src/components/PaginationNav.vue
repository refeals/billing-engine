<script setup lang="ts">
import type { PageMeta } from '@/api/types'
import BaseButton from '@/components/BaseButton.vue'

defineProps<{ meta: PageMeta; noun: string; disabled?: boolean }>()
defineEmits<{ change: [page: number] }>()
</script>

<template>
  <nav
    v-if="meta.total_pages > 1"
    class="flex items-center justify-between text-sm text-ink-muted"
    aria-label="Pagination"
  >
    <span>Page {{ meta.page }} of {{ meta.total_pages }} · {{ meta.total_count }} {{ noun }}</span>
    <div class="flex gap-2">
      <BaseButton :disabled="disabled || meta.page <= 1" @click="$emit('change', meta.page - 1)">
        Previous
      </BaseButton>
      <BaseButton
        :disabled="disabled || meta.page >= meta.total_pages"
        @click="$emit('change', meta.page + 1)"
      >
        Next
      </BaseButton>
    </div>
  </nav>
</template>
