<script setup lang="ts">
import { computed, ref } from 'vue'

import { fetchDashboardSummary } from '@/api/dashboard'
import { toApiError } from '@/api/errors'
import { runReconciliation } from '@/api/reconciliation'
import { SUBSCRIPTION_STATUSES } from '@/api/subscriptions'
import AuditEventItem from '@/components/AuditEventItem.vue'
import BaseButton from '@/components/BaseButton.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockRefresh } from '@/composables/useClockRefresh'
import { formatDateTime, formatMoney } from '@/utils/format'
import { humanize, plural } from '@/utils/text'
import { shareOf } from './share'

const { data: summary, error, loading, reload } = useAsyncData(fetchDashboardSummary)
useClockRefresh(reload)

const totalSubscriptions = computed(() =>
  Object.values(summary.value?.subscriptions_by_status ?? {}).reduce((sum, count) => sum + count, 0),
)
// In the order the schedule runs them; the API only lists steps with open cases.
const dunningSteps = ['day_0_notice', 'day_3_retry', 'day_7_suspend']

const reconciling = ref(false)
const reconcileMessage = ref<string | null>(null)
const reconcileError = ref<string | null>(null)

async function reconcile() {
  reconciling.value = true
  reconcileMessage.value = null
  reconcileError.value = null
  try {
    const run = await runReconciliation()
    reconcileMessage.value = `Checked ${plural(run.subscriptions_checked, 'subscription')}: ${plural(run.discrepancies_found, 'difference')} found.`
    await reload()
  } catch (caught) {
    reconcileError.value = toApiError(caught).message
  } finally {
    reconciling.value = false
  }
}

const tileClass =
  'block rounded-lg border border-border bg-surface p-4 transition-colors hover:border-accent'
</script>

<template>
  <div class="space-y-6" :aria-busy="loading">
    <p v-if="error" class="text-sm text-danger" role="alert">{{ error.message }}</p>

    <template v-if="summary">
      <p class="text-xs text-ink-faint">Figures as of {{ formatDateTime(summary.simulated_now) }}</p>

      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <RouterLink :to="{ name: 'subscriptions' }" :class="tileClass">
          <p class="text-xs text-ink-muted">MRR</p>
          <p class="mt-1 text-2xl font-semibold">{{ formatMoney(summary.mrr_cents) }}</p>
          <p class="mt-1 text-xs text-ink-faint">
            from {{ plural(summary.paying_subscriptions, 'paying subscription') }}
          </p>
        </RouterLink>
        <RouterLink :to="{ name: 'subscriptions', query: { status: 'active' } }" :class="tileClass">
          <p class="text-xs text-ink-muted">Active</p>
          <p class="mt-1 text-2xl font-semibold">{{ summary.subscriptions_by_status.active }}</p>
          <p class="mt-1 text-xs text-ink-faint">
            {{ summary.subscriptions_by_status.trialing }} more in trial
          </p>
        </RouterLink>
        <RouterLink :to="{ name: 'dunning' }" :class="tileClass">
          <p class="text-xs text-ink-muted">Past due</p>
          <p class="mt-1 text-2xl font-semibold">{{ summary.subscriptions_by_status.past_due }}</p>
          <p
            class="mt-1 text-xs"
            :class="summary.dunning.amount_at_risk_cents > 0 ? 'text-status-past-due' : 'text-ink-faint'"
          >
            {{ formatMoney(summary.dunning.amount_at_risk_cents) }} at risk in
            {{ plural(summary.dunning.open_cases, 'dunning case') }}
          </p>
        </RouterLink>
        <RouterLink :to="{ name: 'reconciliation' }" :class="tileClass">
          <p class="text-xs text-ink-muted">Open discrepancies</p>
          <p
            class="mt-1 text-2xl font-semibold"
            :class="summary.open_discrepancies > 0 ? 'text-danger' : ''"
          >
            {{ summary.open_discrepancies }}
          </p>
          <p class="mt-1 text-xs text-ink-faint">
            {{ summary.open_discrepancies > 0 ? 'Engine and provider disagree' : 'Engine and provider agree' }}
          </p>
        </RouterLink>
      </div>

      <div class="grid gap-6 lg:grid-cols-2">
        <section class="space-y-3 rounded-lg border border-border bg-surface p-4">
          <h2 class="text-sm font-semibold">Subscriptions by status</h2>
          <ul class="space-y-2">
            <li v-for="status in SUBSCRIPTION_STATUSES" :key="status">
              <RouterLink
                :to="{ name: 'subscriptions', query: { status } }"
                class="grid grid-cols-[6.5rem_1fr_2.5rem] items-center gap-3 text-sm"
              >
                <StatusBadge :status="status" />
                <span class="h-2 overflow-hidden rounded-full bg-canvas">
                  <span
                    class="block h-full rounded-full bg-accent"
                    :style="{ width: `${shareOf(summary.subscriptions_by_status[status], totalSubscriptions)}%` }"
                  />
                </span>
                <span class="text-right tabular-nums">{{ summary.subscriptions_by_status[status] }}</span>
              </RouterLink>
            </li>
          </ul>

          <h3 class="pt-2 text-sm font-semibold">Open dunning cases by last step</h3>
          <ul class="space-y-1 text-sm">
            <li v-for="step in dunningSteps" :key="step" class="flex justify-between">
              <span class="text-ink-muted">{{ humanize(step) }}</span>
              <span class="tabular-nums">{{ summary.dunning.by_step[step] ?? 0 }}</span>
            </li>
          </ul>
        </section>

        <section class="space-y-3 rounded-lg border border-border bg-surface p-4">
          <div class="flex items-center justify-between">
            <h2 class="text-sm font-semibold">Recent activity</h2>
            <RouterLink :to="{ name: 'audit-log' }" class="text-sm text-accent hover:text-accent-strong">
              Audit log →
            </RouterLink>
          </div>
          <ul v-if="summary.recent_events.length > 0" class="space-y-3">
            <AuditEventItem v-for="event in summary.recent_events" :key="event.id" :event="event" />
          </ul>
          <p v-else class="text-sm text-ink-muted">Nothing has happened yet.</p>
        </section>
      </div>
    </template>

    <section class="flex flex-wrap items-center gap-3">
      <RouterLink
        :to="{ name: 'scenario-lab' }"
        class="inline-flex items-center rounded-md border border-transparent bg-accent px-3 py-1.5 text-sm font-medium text-white transition-colors hover:bg-accent-strong"
      >
        Open Scenario Lab
      </RouterLink>
      <BaseButton :disabled="reconciling" @click="reconcile">
        {{ reconciling ? 'Reconciling…' : 'Run reconciliation' }}
      </BaseButton>
      <p v-if="reconcileMessage" class="text-sm text-ink-muted" role="status">{{ reconcileMessage }}</p>
      <p v-if="reconcileError" class="text-sm text-danger" role="alert">{{ reconcileError }}</p>
    </section>
  </div>
</template>
