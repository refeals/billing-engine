<script setup lang="ts">
import { useRoute } from 'vue-router'

import AppLayout from '@/layouts/AppLayout.vue'

// The login renders on its own: the sidebar and the clock call the API, which needs a
// session.
const route = useRoute()
</script>

<template>
  <RouterView v-if="route.meta.public" />
  <AppLayout v-else />
</template>
