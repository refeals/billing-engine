<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter, type LocationQuery } from 'vue-router'

import { ApiError } from '@/api/client'
import {
  ACTOR_TYPES,
  fetchBillingEvents,
  type BillingEvent,
  type BillingEventFilters,
  type BillingEventsMeta,
} from '@/api/billingEvents'
import AuditEventItem from '@/components/AuditEventItem.vue'
import { useClockRefresh } from '@/composables/useClockRefresh'

const FILTER_KEYS = ['event_type', 'actor_type', 'from', 'to'] as const
type FilterKey = (typeof FILTER_KEYS)[number]

const route = useRoute()
const router = useRouter()

const events = ref<BillingEvent[]>([])
const meta = ref<BillingEventsMeta | null>(null)
const loading = ref(false)
const error = ref<ApiError | null>(null)
let latestRequest = 0

// Filters live in the URL so a filtered view can be shared or bookmarked.
function filtersFrom(query: LocationQuery): BillingEventFilters {
  const filters: BillingEventFilters = {}
  for (const key of [...FILTER_KEYS, 'page'] as const) {
    const value = query[key]
    if (typeof value === 'string' && value !== '') filters[key] = value
  }
  return filters
}

const filters = computed(() => filtersFrom(route.query))
const hasFilters = computed(() => FILTER_KEYS.some((key) => filters.value[key]))
const page = computed(() => Number(filters.value.page ?? '1'))

async function load() {
  const request = ++latestRequest
  loading.value = true
  error.value = null

  try {
    const result = await fetchBillingEvents(filters.value)
    // A slower, older request must not overwrite the results of a newer filter.
    if (request !== latestRequest) return
    events.value = result.data
    meta.value = result.meta
  } catch (caught) {
    if (request !== latestRequest) return
    error.value =
      caught instanceof ApiError ? caught : new ApiError(0, 'unknown_error', String(caught))
  } finally {
    if (request === latestRequest) loading.value = false
  }
}

function setFilter(key: FilterKey, value: string) {
  const query = { ...route.query, [key]: value || undefined }
  delete query.page
  router.replace({ query })
}

function clearFilters() {
  router.replace({ query: {} })
}

function goToPage(target: number) {
  router.replace({ query: { ...route.query, page: target > 1 ? String(target) : undefined } })
}

function inputValue(event: Event): string {
  return (event.target as HTMLInputElement | HTMLSelectElement).value
}

useClockRefresh(load)
// Leaving the page also changes route.query; only react to changes made on this page.
watch(
  () => route.query,
  () => {
    if (route.name === 'audit-log') load()
  },
)
</script>

<template>
  <div class="space-y-4">
    <p class="max-w-3xl text-sm text-ink-muted">
      Every state change in the system, in the order it happened. Rows are append-only: the database
      refuses to update or delete them.
    </p>

    <form
      class="flex flex-wrap items-end gap-3 rounded-lg border border-border bg-surface p-4"
      @submit.prevent
    >
      <label class="flex flex-col gap-1 text-xs text-ink-muted">
        Event type
        <select
          class="rounded-md border border-border bg-surface px-2 py-1.5 text-sm text-ink"
          :value="filters.event_type ?? ''"
          @change="setFilter('event_type', inputValue($event))"
        >
          <option value="">All types</option>
          <option v-for="type in meta?.event_types ?? []" :key="type" :value="type">
            {{ type }}
          </option>
        </select>
      </label>

      <label class="flex flex-col gap-1 text-xs text-ink-muted">
        Actor
        <select
          class="rounded-md border border-border bg-surface px-2 py-1.5 text-sm text-ink"
          :value="filters.actor_type ?? ''"
          @change="setFilter('actor_type', inputValue($event))"
        >
          <option value="">All actors</option>
          <option v-for="actor in ACTOR_TYPES" :key="actor" :value="actor">{{ actor }}</option>
        </select>
      </label>

      <label class="flex flex-col gap-1 text-xs text-ink-muted">
        From
        <input
          type="date"
          class="rounded-md border border-border bg-surface px-2 py-1 text-sm text-ink"
          :value="filters.from ?? ''"
          @change="setFilter('from', inputValue($event))"
        />
      </label>

      <label class="flex flex-col gap-1 text-xs text-ink-muted">
        To
        <input
          type="date"
          class="rounded-md border border-border bg-surface px-2 py-1 text-sm text-ink"
          :value="filters.to ?? ''"
          @change="setFilter('to', inputValue($event))"
        />
      </label>

      <button
        v-if="hasFilters"
        type="button"
        class="px-2 py-1.5 text-sm text-accent hover:text-accent-strong"
        @click="clearFilters"
      >
        Clear filters
      </button>
    </form>

    <p v-if="error" class="text-sm text-danger" role="alert">{{ error.message }}</p>

    <section class="rounded-lg border border-border bg-surface" :aria-busy="loading">
      <ul v-if="events.length > 0">
        <AuditEventItem v-for="event in events" :key="event.id" :event="event" />
      </ul>

      <p v-else-if="!loading && !error" class="px-4 py-10 text-center text-sm text-ink-muted">
        {{
          hasFilters
            ? 'No events match these filters.'
            : 'No events yet. Advance the clock to record the first one.'
        }}
      </p>
    </section>

    <nav
      v-if="meta && meta.total_pages > 1"
      class="flex items-center justify-between text-sm text-ink-muted"
    >
      <span> Page {{ meta.page }} of {{ meta.total_pages }} · {{ meta.total_count }} events </span>
      <div class="flex gap-2">
        <button
          type="button"
          class="rounded-md border border-border bg-surface px-3 py-1 disabled:opacity-40"
          :disabled="page <= 1 || loading"
          @click="goToPage(page - 1)"
        >
          Previous
        </button>
        <button
          type="button"
          class="rounded-md border border-border bg-surface px-3 py-1 disabled:opacity-40"
          :disabled="page >= meta.total_pages || loading"
          @click="goToPage(page + 1)"
        >
          Next
        </button>
      </div>
    </nav>
  </div>
</template>
