<script setup lang="ts">
import { computed, ref, useTemplateRef, watch } from 'vue'

import { toApiError } from '@/api/errors'
import {
  fetchScenarioRuns,
  fetchScenarios,
  resetDemoData,
  runScenario,
  type DemoSummary,
  type ScenarioRun,
} from '@/api/scenarios'
import BaseBadge from '@/components/BaseBadge.vue'
import BaseButton from '@/components/BaseButton.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import PaginationNav from '@/components/PaginationNav.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockStore } from '@/stores/clock'
import { formatDate } from '@/utils/format'
import EmitEventForm from './EmitEventForm.vue'
import ProviderOutbox from './ProviderOutbox.vue'
import ScenarioRunPanel from './ScenarioRunPanel.vue'

const clock = useClockStore()

const scenarios = useAsyncData(fetchScenarios)
scenarios.reload()

const runsPage = ref(1)
const runs = useAsyncData(() => fetchScenarioRuns({ page: runsPage.value }))
runs.reload()
watch(runsPage, runs.reload)

const selectedRun = ref<ScenarioRun | null>(null)
const runningKey = ref<string | null>(null)
const runError = ref<string | null>(null)
// One action at a time: every scenario and the reset move the same clock.
const busy = computed(() => runningKey.value !== null || resetPending.value)

async function run(key: string) {
  runningKey.value = key
  runError.value = null
  try {
    selectedRun.value = await runScenario(key)
  } catch (caught) {
    runError.value = toApiError(caught).message
  } finally {
    // Even a failed request may have moved the clock before it broke.
    runsPage.value = 1
    await Promise.all([runs.reload(), clock.timeMoved()])
    runningKey.value = null
  }
}

const resetOpen = ref(false)
const resetPending = ref(false)
const resetError = ref<string | null>(null)
const resetSummary = ref<DemoSummary | null>(null)

async function reset() {
  resetPending.value = true
  resetError.value = null
  try {
    resetSummary.value = await resetDemoData()
    resetOpen.value = false
    selectedRun.value = null
  } catch (caught) {
    resetError.value = toApiError(caught).message
  } finally {
    // The wipe commits before seeding starts, so a failure can still have changed everything.
    runsPage.value = 1
    await Promise.all([runs.reload(), clock.timeMoved()])
    resetPending.value = false
  }
}

const outbox = useTemplateRef('outbox')
</script>

<template>
  <div class="space-y-8">
    <p class="rounded-lg border border-status-past-due/30 bg-status-past-due/5 p-3 text-sm text-ink-muted">
      Scenarios run the real services against the <strong>shared</strong> simulated clock: while
      one advances time, every other subscription renews, retries and expires too. Each run
      creates its own customer, so runs never interfere with each other's checks.
    </p>

    <section class="space-y-3">
      <h2 class="text-sm font-semibold">Scenarios</h2>
      <p v-if="scenarios.error.value" class="text-sm text-danger" role="alert">
        {{ scenarios.error.value.message }}
      </p>
      <p v-if="runError" class="text-sm text-danger" role="alert">{{ runError }}</p>
      <ul class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <li
          v-for="scenario in scenarios.data.value?.data ?? []"
          :key="scenario.key"
          class="flex flex-col justify-between gap-3 rounded-lg border border-border bg-surface p-4"
        >
          <div class="space-y-1">
            <h3 class="text-sm font-semibold">{{ scenario.title }}</h3>
            <p class="text-sm text-ink-muted">{{ scenario.description }}</p>
          </div>
          <div class="flex items-center justify-between gap-2">
            <code class="text-xs text-ink-faint">{{ scenario.key }}</code>
            <BaseButton variant="primary" :disabled="busy" @click="run(scenario.key)">
              {{ runningKey === scenario.key ? 'Running…' : 'Run' }}
            </BaseButton>
          </div>
        </li>
      </ul>
    </section>

    <ScenarioRunPanel v-if="selectedRun" :key="selectedRun.id" :run="selectedRun" />

    <section class="space-y-3">
      <h2 class="text-sm font-semibold">Recent runs</h2>
      <p v-if="runs.error.value" class="text-sm text-danger" role="alert">
        {{ runs.error.value.message }}
      </p>
      <p
        v-else-if="runs.data.value && runs.data.value.data.length === 0"
        class="text-sm text-ink-muted"
      >
        No scenario has run yet.
      </p>
      <ul
        v-else
        class="divide-y divide-border rounded-lg border border-border bg-surface"
        :aria-busy="runs.loading.value"
      >
        <li v-for="item in runs.data.value?.data ?? []" :key="item.id">
          <button
            type="button"
            class="flex w-full flex-wrap items-center justify-between gap-2 px-4 py-2.5 text-left text-sm hover:bg-canvas"
            :aria-pressed="selectedRun?.id === item.id"
            @click="selectedRun = item"
          >
            <span>
              {{ item.title }} <span class="text-xs text-ink-faint">#{{ item.id }}</span>
            </span>
            <span class="flex items-center gap-3">
              <span class="text-xs text-ink-muted">{{ formatDate(item.started_at) }}</span>
              <BaseBadge :tone="item.status === 'passed' ? 'success' : 'danger'">
                {{ item.status }}
              </BaseBadge>
            </span>
          </button>
        </li>
      </ul>
      <PaginationNav
        v-if="runs.data.value"
        :meta="runs.data.value.meta"
        noun="runs"
        :disabled="runs.loading.value"
        @change="runsPage = $event"
      />
    </section>

    <details class="group space-y-6">
      <summary class="cursor-pointer text-sm font-semibold">
        Advanced: make the provider speak up, and the whole outbox
      </summary>
      <div class="mt-4 space-y-6">
        <EmitEventForm @emitted="outbox?.showFirstPage()" />
        <ProviderOutbox ref="outbox">
          <template #heading>
            <h2 class="text-sm font-semibold">Provider outbox</h2>
            <p class="text-sm text-ink-muted">
              Everything the fake Stripe emitted, delivered or not. It never reads the engine's
              tables, so it is an independent record of what the provider believes.
            </p>
          </template>
        </ProviderOutbox>
      </div>
    </details>

    <section class="space-y-3 rounded-lg border border-danger/30 p-4">
      <h2 class="text-sm font-semibold">Reset demo data</h2>
      <p class="text-sm text-ink-muted">
        Deletes everything, including the append-only history, and rebuilds the demo studios
        from 2026-01-05 through about 70 simulated days.
      </p>
      <p v-if="resetSummary" class="text-sm text-status-active" role="status">
        Demo rebuilt: {{ resetSummary.customers }} customers, clock at
        {{ formatDate(resetSummary.simulated_now) }}, {{ resetSummary.open_discrepancies }} open
        discrepancies.
      </p>
      <BaseButton variant="danger" :disabled="busy" @click="resetOpen = true">
        Reset demo data
      </BaseButton>
    </section>

    <ConfirmDialog
      v-model:open="resetOpen"
      title="Reset demo data?"
      :confirm-label="resetPending ? 'Resetting…' : 'Delete everything and reseed'"
      :pending="resetPending"
      :error="resetError"
      @confirm="reset"
    >
      <p>
        Every customer, subscription, invoice, webhook and audit event is deleted, then the demo
        is seeded again. This is the only path in the app that removes history.
      </p>
      <p>Rebuilding replays about 70 simulated days and takes around 15 seconds.</p>
    </ConfirmDialog>
  </div>
</template>
