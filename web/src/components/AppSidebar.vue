<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'

import BaseButton from '@/components/BaseButton.vue'
import { navigation } from '@/router/navigation'
import { useAuthStore } from '@/stores/auth'

// Sections stay highlighted on their detail pages (/customers/12); the dashboard ('/')
// only on itself, since every path starts with '/'.
const activeClass = 'bg-canvas font-medium text-ink'

const auth = useAuthStore()
const router = useRouter()
const signingOut = ref(false)

async function signOut() {
  signingOut.value = true
  await auth.signOut()
  await router.replace({ name: 'login' })
}
</script>

<template>
  <nav
    class="flex flex-col border-b border-border bg-surface md:sticky md:top-0 md:h-screen md:w-60 md:shrink-0 md:overflow-y-auto md:border-r md:border-b-0"
  >
    <div class="px-5 py-4">
      <p class="text-sm font-semibold">Billing Engine</p>
      <p class="text-xs text-ink-muted">Studio subscriptions back-office</p>
    </div>

    <div v-for="group in navigation" :key="group.label" class="px-3 pb-4">
      <p class="px-2 pb-1 text-xs font-medium tracking-wide text-ink-faint uppercase">
        {{ group.label }}
      </p>

      <ul>
        <li v-for="item in group.items" :key="item.to">
          <RouterLink
            :to="item.to"
            class="block rounded-md px-2 py-1.5 text-sm text-ink-muted hover:bg-canvas hover:text-ink"
            :active-class="item.to === '/' ? '' : activeClass"
            :exact-active-class="activeClass"
          >
            {{ item.label }}
          </RouterLink>
        </li>
      </ul>
    </div>
    <div class="mt-auto border-t border-border px-5 py-4">
      <p class="truncate text-xs text-ink-muted" :title="auth.user?.email">
        {{ auth.user?.email }}
      </p>
      <BaseButton variant="ghost" class="-ml-3 cursor-pointer" :disabled="signingOut" @click="signOut">
        Sign out
      </BaseButton>
    </div>
  </nav>
</template>
