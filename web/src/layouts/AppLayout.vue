<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'

import AppSidebar from '@/components/AppSidebar.vue'
import ClockWidget from '@/components/ClockWidget.vue'

const route = useRoute()
const title = computed(() => route.meta.title ?? '')
</script>

<template>
  <div class="flex min-h-screen flex-col md:flex-row">
    <AppSidebar />

    <div class="flex min-w-0 flex-1 flex-col">
      <header
        class="flex flex-wrap items-center justify-between gap-4 border-b border-border bg-surface px-6 py-3"
      >
        <h1 class="text-lg font-semibold">{{ title }}</h1>
        <ClockWidget />
      </header>

      <main class="flex-1 p-6">
        <RouterView />
      </main>
    </div>
  </div>
</template>
