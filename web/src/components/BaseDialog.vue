<script setup lang="ts">
import { onMounted, useTemplateRef, watch } from 'vue'

const open = defineModel<boolean>('open', { required: true })
defineProps<{ title: string }>()

// The native <dialog> gives focus trapping, Esc to close and a backdrop for free.
const dialog = useTemplateRef<HTMLDialogElement>('dialog')

function sync(isOpen: boolean) {
  if (!dialog.value) return
  if (isOpen && !dialog.value.open) dialog.value.showModal()
  if (!isOpen && dialog.value.open) dialog.value.close()
}

watch(open, sync)
onMounted(() => sync(open.value))
</script>

<template>
  <dialog
    ref="dialog"
    class="m-auto w-full max-w-md rounded-lg border border-border bg-surface p-0 text-ink shadow-xl backdrop:bg-ink/30"
    @close="open = false"
  >
    <div v-if="open" class="p-5">
      <h2 class="mb-4 text-base font-semibold">{{ title }}</h2>
      <slot />
    </div>
  </dialog>
</template>
