<script setup lang="ts">
import { isCheck, type ScenarioRun } from '@/api/scenarios'
import BaseBadge from '@/components/BaseBadge.vue'
import { formatDate } from '@/utils/format'
import ProviderOutbox from './ProviderOutbox.vue'

defineProps<{ run: ScenarioRun }>()

const linkClass = 'text-accent hover:text-accent-strong'
</script>

<template>
  <section class="space-y-4 rounded-lg border border-border bg-surface p-4" aria-live="polite">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="flex items-center gap-2">
        <h2 class="text-sm font-semibold">{{ run.title }}</h2>
        <BaseBadge :tone="run.status === 'passed' ? 'success' : 'danger'">
          {{ run.status }}
        </BaseBadge>
        <span class="text-xs text-ink-faint">run #{{ run.id }}</span>
      </div>
      <nav v-if="run.subscription_id" class="flex flex-wrap gap-4 text-sm" aria-label="Open">
        <RouterLink :to="{ name: 'subscription', params: { id: run.subscription_id } }" :class="linkClass">
          Subscription →
        </RouterLink>
        <RouterLink
          :to="{ name: 'subscription-history', params: { id: run.subscription_id } }"
          :class="linkClass"
        >
          History →
        </RouterLink>
        <RouterLink
          v-if="run.customer_id"
          :to="{ name: 'customer', params: { id: run.customer_id } }"
          :class="linkClass"
        >
          Customer and invoices →
        </RouterLink>
        <RouterLink
          :to="{ name: 'reconciliation', query: { subscription_id: run.subscription_id } }"
          :class="linkClass"
        >
          Reconciliation →
        </RouterLink>
      </nav>
    </div>

    <p v-if="run.error" class="text-sm text-danger" role="alert">{{ run.error }}</p>

    <ol class="space-y-1.5 text-sm">
      <li v-for="(entry, index) in run.log" :key="index" class="flex gap-3">
        <span class="w-24 shrink-0 text-xs leading-5 text-ink-faint">{{ formatDate(entry.at) }}</span>
        <span :class="isCheck(entry) ? 'text-status-active' : ''">
          {{ entry.step }}
          <span v-if="entry.detail" class="text-ink-muted"> — {{ entry.detail }}</span>
        </span>
      </li>
    </ol>

    <ProviderOutbox v-if="run.subscription_id" :scenario-run-id="run.id">
      <template #heading>
        <h3 class="text-sm font-semibold">Events this run made the provider send</h3>
        <p class="text-sm text-ink-muted">
          Only this scenario's subscription; other subscriptions renewing on the shared clock are
          left out.
        </p>
      </template>
    </ProviderOutbox>
  </section>
</template>
