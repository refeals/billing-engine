<script setup lang="ts">
import { computed, ref, watch } from 'vue'

import { toApiError } from '@/api/errors'
import { archivePlan, fetchPlans, type Plan } from '@/api/plans'
import BaseBadge from '@/components/BaseBadge.vue'
import BaseButton from '@/components/BaseButton.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import EmptyState from '@/components/EmptyState.vue'
import PaginationNav from '@/components/PaginationNav.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockRefresh } from '@/composables/useClockRefresh'
import { formatDate, formatMoney } from '@/utils/format'
import PlanFormDialog from './PlanFormDialog.vue'

const includeArchived = ref(false)
const page = ref(1)
const creating = ref(false)

const { data, error, loading, reload } = useAsyncData(() =>
  fetchPlans({ includeArchived: includeArchived.value, page: page.value }),
)
const plans = computed(() => data.value?.data ?? [])

watch(includeArchived, () => {
  page.value = 1
  reload()
})
watch(page, reload)
useClockRefresh(reload)

const archiving = ref<Plan | null>(null)
const archiveOpen = computed({
  get: () => archiving.value !== null,
  set: (open) => {
    if (!open) archiving.value = null
  },
})
const archivePending = ref(false)
const archiveError = ref<string | null>(null)

function askToArchive(plan: Plan) {
  archiveError.value = null
  archiving.value = plan
}

async function confirmArchive() {
  if (!archiving.value) return
  archivePending.value = true
  try {
    await archivePlan(archiving.value.id)
    archiving.value = null
    await reload()
  } catch (caught) {
    archiveError.value = toApiError(caught).message
  } finally {
    archivePending.value = false
  }
}
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <label class="flex items-center gap-2 text-sm text-ink-muted">
        <input v-model="includeArchived" type="checkbox" />
        Show archived plans
      </label>
      <BaseButton variant="primary" @click="creating = true">New plan</BaseButton>
    </div>

    <p v-if="error" class="text-sm text-danger" role="alert">{{ error.message }}</p>

    <section
      class="overflow-x-auto rounded-lg border border-border bg-surface"
      :aria-busy="loading"
    >
      <table v-if="plans.length > 0" class="w-full text-sm">
        <thead class="border-b border-border text-left text-xs text-ink-faint">
          <tr>
            <th class="px-4 py-2 font-medium">Plan</th>
            <th class="px-4 py-2 font-medium">Price</th>
            <th class="px-4 py-2 font-medium">Trial</th>
            <th class="px-4 py-2 font-medium">Status</th>
            <th class="px-4 py-2"><span class="sr-only">Actions</span></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="plan in plans" :key="plan.id" class="border-b border-border last:border-b-0">
            <td class="px-4 py-3">
              <p class="font-medium">{{ plan.name }}</p>
              <p class="font-mono text-xs text-ink-faint">{{ plan.code }}</p>
            </td>
            <td class="px-4 py-3 tabular-nums">
              {{ formatMoney(plan.amount_cents) }}
              <span class="text-ink-muted">/ {{ plan.interval }}</span>
            </td>
            <td class="px-4 py-3 text-ink-muted">
              {{ plan.trial_days > 0 ? `${plan.trial_days} days` : 'None' }}
            </td>
            <td class="px-4 py-3">
              <BaseBadge v-if="plan.active" tone="success">Active</BaseBadge>
              <BaseBadge v-else :title="`Archived ${formatDate(plan.archived_at!)}`">
                Archived
              </BaseBadge>
            </td>
            <td class="px-4 py-3 text-right">
              <BaseButton v-if="plan.active" variant="ghost" @click="askToArchive(plan)">
                Archive
              </BaseButton>
            </td>
          </tr>
        </tbody>
      </table>

      <EmptyState
        v-else-if="!loading && !error"
        title="No plans yet"
        description="Plans define what studios pay and how often."
      >
        <BaseButton variant="primary" @click="creating = true">Create the first plan</BaseButton>
      </EmptyState>
    </section>

    <PaginationNav
      v-if="data"
      :meta="data.meta"
      noun="plans"
      :disabled="loading"
      @change="page = $event"
    />

    <PlanFormDialog v-model:open="creating" @created="reload" />

    <ConfirmDialog
      v-model:open="archiveOpen"
      title="Archive plan"
      confirm-label="Archive plan"
      :pending="archivePending"
      :error="archiveError"
      @confirm="confirmArchive"
    >
      <p>
        <strong class="text-ink">{{ archiving?.name }}</strong> will no longer be offered to new
        subscribers or as a plan change. Current subscribers keep it.
      </p>
    </ConfirmDialog>
  </div>
</template>
