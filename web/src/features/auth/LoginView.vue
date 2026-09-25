<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { toApiError } from '@/api/errors'
import { DEMO_CREDENTIALS } from '@/api/session'
import BaseButton from '@/components/BaseButton.vue'
import FormField from '@/components/FormField.vue'
import { safeRedirect } from '@/router/redirect'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const route = useRoute()
const router = useRouter()

const form = reactive({ email: '', password: '' })
const pending = ref(false)
const error = ref<string | null>(null)

const inputClass = 'rounded-md border border-border bg-surface px-2.5 py-1.5 text-sm'

function useDemoCredentials() {
  form.email = DEMO_CREDENTIALS.email
  form.password = DEMO_CREDENTIALS.password
}

async function submit() {
  pending.value = true
  error.value = null
  try {
    await auth.signIn(form.email, form.password)
    await router.replace(safeRedirect(route.query.redirect))
  } catch (caught) {
    error.value = toApiError(caught).message
  } finally {
    pending.value = false
  }
}
</script>

<template>
  <main class="flex min-h-screen items-center justify-center bg-canvas px-4 py-10">
    <div class="w-full max-w-sm space-y-4">
      <div class="text-center">
        <p class="text-lg font-semibold">Billing Engine</p>
        <p class="text-sm text-ink-muted">Studio subscriptions back-office</p>
      </div>

      <form
        class="space-y-4 rounded-lg border border-border bg-surface p-6"
        novalidate
        @submit.prevent="submit"
      >
        <h1 class="text-base font-semibold">Sign in</h1>
        <FormField label="Email">
          <input
            v-model="form.email"
            :class="inputClass"
            type="email"
            autocomplete="username"
            required
          />
        </FormField>
        <FormField label="Password">
          <input
            v-model="form.password"
            :class="inputClass"
            type="password"
            autocomplete="current-password"
            required
          />
        </FormField>
        <p v-if="error" class="text-sm text-danger" role="alert">{{ error }}</p>
        <BaseButton type="submit" variant="primary" class="w-full" :disabled="pending">
          {{ pending ? 'Signing in…' : 'Sign in' }}
        </BaseButton>
      </form>

      <section class="space-y-2 rounded-lg border border-accent/30 bg-accent/5 p-4 text-sm">
        <h2 class="font-semibold">Demo credentials</h2>
        <p class="text-ink-muted">
          This is a portfolio demo with fictional data; everyone signs in as the same operator.
        </p>
        <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1">
          <dt class="text-ink-muted">Email</dt>
          <dd class="font-mono select-all">{{ DEMO_CREDENTIALS.email }}</dd>
          <dt class="text-ink-muted">Password</dt>
          <dd class="font-mono select-all">{{ DEMO_CREDENTIALS.password }}</dd>
        </dl>
        <BaseButton variant="secondary" class="mt-2 w-full cursor-pointer" @click="useDemoCredentials">
          Use demo credentials
        </BaseButton>
      </section>
    </div>
  </main>
</template>
