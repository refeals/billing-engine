<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { toApiError } from '@/api/errors'
import {
  fetchDiscrepancies,
  fetchReconciliationRuns,
  groupBySubscription,
  RESOLUTION_LABELS,
  resolveDiscrepancy,
  runReconciliation,
  type Discrepancy,
  type Resolution,
} from '@/api/reconciliation'
import BaseButton from '@/components/BaseButton.vue'
import BaseDialog from '@/components/BaseDialog.vue'
import EmptyState from '@/components/EmptyState.vue'
import FormField from '@/components/FormField.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockRefresh } from '@/composables/useClockRefresh'
import { formatDateTime } from '@/utils/format'
import { humanize } from '@/utils/text'

const route = useRoute()
const router = useRouter()
const subscriptionFilter = computed(() =>
  typeof route.query.subscription_id === 'string' ? route.query.subscription_id : '',
)

const discrepancies = useAsyncData(() =>
  fetchDiscrepancies({ status: 'open', subscription_id: subscriptionFilter.value }),
)
const runs = useAsyncData(fetchReconciliationRuns)
const groups = computed(() => groupBySubscription(discrepancies.data.value?.data ?? []))

function reloadAll() {
  discrepancies.reload()
  runs.reload()
}

useClockRefresh(reloadAll)
watch(subscriptionFilter, () => discrepancies.reload())

const running = ref(false)
const actionError = ref<string | null>(null)

async function runNow() {
  running.value = true
  actionError.value = null
  try {
    await runReconciliation(subscriptionFilter.value ? Number(subscriptionFilter.value) : undefined)
    reloadAll()
  } catch (caught) {
    actionError.value = toApiError(caught).message
  } finally {
    running.value = false
  }
}

const resolvingId = ref<number | null>(null)

async function resolve(discrepancy: Discrepancy, strategy: Resolution, note?: string) {
  resolvingId.value = discrepancy.id
  actionError.value = null
  try {
    await resolveDiscrepancy(discrepancy.id, strategy, note)
    reloadAll()
  } catch (caught) {
    actionError.value = toApiError(caught).message
  } finally {
    resolvingId.value = null
  }
}

// Acknowledging needs a note: it records a decision to leave things as they are.
const acknowledging = ref<Discrepancy | null>(null)
const acknowledgeOpen = computed({
  get: () => acknowledging.value !== null,
  set: (open) => {
    if (!open) acknowledging.value = null
  },
})
const note = ref('')

function startAcknowledge(discrepancy: Discrepancy) {
  note.value = ''
  acknowledging.value = discrepancy
}

async function confirmAcknowledge() {
  if (!acknowledging.value || note.value.trim() === '') return
  const target = acknowledging.value
  acknowledging.value = null
  await resolve(target, 'acknowledge', note.value.trim())
}

function onResolution(discrepancy: Discrepancy, strategy: Resolution) {
  if (strategy === 'acknowledge') startAcknowledge(discrepancy)
  else resolve(discrepancy, strategy)
}

function describe(discrepancy: Discrepancy) {
  if (discrepancy.kind === 'undelivered_event')
    return 'The provider sent this event; the engine never received it.'
  if (discrepancy.kind === 'failed_event') return 'The event arrived but its handler failed.'
  return `Engine: ${discrepancy.internal_value ?? '—'} · Provider: ${discrepancy.expected_value ?? '—'}`
}

function clearFilter() {
  router.replace({ query: {} })
}
</script>

<template>
  <div class="space-y-6">
    <div class="flex flex-wrap items-start justify-between gap-4">
      <p class="max-w-3xl text-sm text-ink-muted">
        Compares what the engine believes with the payment provider's own history of events, and
        lists every difference: lost webhooks, failed handlers, changes the provider never heard
        about. Nothing is corrected automatically. A full check also runs at the end of every
        simulated day.
      </p>
      <BaseButton variant="primary" :disabled="running" @click="runNow">
        {{ subscriptionFilter ? 'Check this subscription' : 'Run reconciliation' }}
      </BaseButton>
    </div>

    <p v-if="subscriptionFilter" class="text-sm">
      Showing subscription #{{ subscriptionFilter }} only.
      <button type="button" class="text-accent hover:text-accent-strong" @click="clearFilter">
        Show all
      </button>
    </p>

    <p v-if="actionError || discrepancies.error.value" class="text-sm text-danger" role="alert">
      {{ actionError ?? discrepancies.error.value?.message }}
    </p>

    <section class="space-y-4">
      <h2 class="text-sm font-semibold">Open discrepancies</h2>
      <div
        v-for="group in groups"
        :key="group.subscription.id"
        class="rounded-lg border border-border bg-surface"
      >
        <RouterLink
          :to="{ name: 'subscription', params: { id: group.subscription.id } }"
          class="block border-b border-border px-5 py-3 text-sm font-semibold hover:text-accent"
        >
          {{ group.subscription.customer.name }} · subscription #{{ group.subscription.id }}
          <span class="font-normal text-ink-muted"
            >({{ humanize(group.subscription.status) }})</span
          >
        </RouterLink>
        <ul>
          <li
            v-for="discrepancy in group.items"
            :key="discrepancy.id"
            class="space-y-2 border-b border-border px-5 py-3 last:border-b-0"
          >
            <div class="flex flex-wrap items-baseline justify-between gap-2">
              <p class="text-sm font-medium">{{ humanize(discrepancy.kind) }}</p>
              <p class="font-mono text-xs text-ink-faint">{{ discrepancy.subject_key }}</p>
            </div>
            <p class="text-sm text-ink-muted">{{ describe(discrepancy) }}</p>
            <p v-if="discrepancy.evidence_event_ids.length > 0" class="text-xs text-ink-faint">
              Evidence:
              <span
                v-for="eventId in discrepancy.evidence_event_ids"
                :key="eventId"
                class="mr-2 font-mono"
              >
                {{ eventId }}
              </span>
              <RouterLink to="/simulator" class="text-accent hover:text-accent-strong"
                >provider outbox →</RouterLink
              >
            </p>
            <div class="flex flex-wrap gap-2">
              <BaseButton
                v-for="strategy in discrepancy.available_resolutions"
                :key="strategy"
                :variant="strategy === 'acknowledge' ? 'secondary' : 'primary'"
                :disabled="resolvingId === discrepancy.id"
                @click="onResolution(discrepancy, strategy)"
              >
                {{ RESOLUTION_LABELS[strategy] }}
              </BaseButton>
              <BaseButton
                v-for="(reason, strategy) in discrepancy.blocked_resolutions"
                :key="strategy"
                disabled
                :title="reason"
              >
                {{ RESOLUTION_LABELS[strategy] }}
              </BaseButton>
            </div>
            <p
              v-for="(reason, strategy) in discrepancy.blocked_resolutions"
              :key="`reason-${strategy}`"
              class="text-xs text-ink-faint"
            >
              {{ reason }}
            </p>
          </li>
        </ul>
      </div>
      <EmptyState
        v-if="groups.length === 0 && !discrepancies.loading.value"
        title="Engine and provider agree"
        description="Drop an event or make the provider disagree in the Scenario Lab, then run a check."
      />
    </section>

    <section class="rounded-lg border border-border bg-surface">
      <h2 class="border-b border-border px-5 py-3 text-sm font-semibold">Recent runs</h2>
      <table class="w-full text-sm">
        <thead class="border-b border-border text-left text-xs text-ink-faint">
          <tr>
            <th class="px-5 py-2 font-medium">When</th>
            <th class="px-5 py-2 font-medium">By</th>
            <th class="px-5 py-2 text-right font-medium">Checked</th>
            <th class="px-5 py-2 text-right font-medium">Found</th>
            <th class="px-5 py-2 text-right font-medium">New</th>
            <th class="px-5 py-2 text-right font-medium">Cleared</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="run in (runs.data.value?.data ?? []).slice(0, 10)"
            :key="run.id"
            class="border-b border-border last:border-b-0"
          >
            <td class="px-5 py-2 text-ink-muted">{{ formatDateTime(run.started_at) }}</td>
            <td class="px-5 py-2">{{ humanize(run.triggered_by) }}</td>
            <td class="px-5 py-2 text-right tabular-nums">{{ run.subscriptions_checked }}</td>
            <td class="px-5 py-2 text-right tabular-nums">{{ run.discrepancies_found }}</td>
            <td class="px-5 py-2 text-right tabular-nums">{{ run.discrepancies_opened }}</td>
            <td class="px-5 py-2 text-right tabular-nums">{{ run.discrepancies_cleared }}</td>
          </tr>
        </tbody>
      </table>
    </section>

    <BaseDialog v-model:open="acknowledgeOpen" title="Acknowledge discrepancy">
      <form class="space-y-4 text-sm" @submit.prevent="confirmAcknowledge">
        <p class="text-ink-muted">
          Nothing will change; the note records why this difference is accepted.
        </p>
        <FormField label="Note">
          <textarea
            v-model="note"
            rows="3"
            class="rounded-md border border-border bg-surface px-2.5 py-1.5 text-sm"
          />
        </FormField>
        <div class="flex justify-end gap-2">
          <BaseButton @click="acknowledgeOpen = false">Cancel</BaseButton>
          <BaseButton type="submit" variant="primary" :disabled="note.trim() === ''"
            >Acknowledge</BaseButton
          >
        </div>
      </form>
    </BaseDialog>
  </div>
</template>
