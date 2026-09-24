<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{
  before?: Record<string, unknown>
  after?: Record<string, unknown>
  context?: Record<string, unknown>
}>()

interface DiffRow {
  key: string
  before: string
  after: string
  changed: boolean
}

const MISSING = '—'

function display(value: unknown): string {
  if (value === undefined) return MISSING
  return typeof value === 'string' ? value : JSON.stringify(value, null, 2)
}

// Top-level keys only: audit payloads are flat snapshots of the fields that changed,
// so a key-by-key table reads better than a line diff.
const rows = computed<DiffRow[]>(() => {
  const before = props.before ?? {}
  const after = props.after ?? {}
  const keys = [...new Set([...Object.keys(before), ...Object.keys(after)])]

  return keys.map((key) => {
    const beforeValue = display(before[key])
    const afterValue = display(after[key])
    return { key, before: beforeValue, after: afterValue, changed: beforeValue !== afterValue }
  })
})

const hasContext = computed(() => Object.keys(props.context ?? {}).length > 0)
</script>

<template>
  <div class="space-y-3 text-xs">
    <table v-if="rows.length > 0" class="w-full border-collapse font-mono">
      <thead>
        <tr class="text-left text-ink-faint">
          <th class="w-1/5 pb-1 font-medium">Field</th>
          <th class="w-2/5 pb-1 font-medium">Before</th>
          <th class="w-2/5 pb-1 font-medium">After</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="row in rows"
          :key="row.key"
          :class="row.changed ? 'bg-accent/5' : ''"
          :data-changed="row.changed"
        >
          <td class="py-1 pr-2 align-top text-ink-muted">{{ row.key }}</td>
          <td class="py-1 pr-2 align-top break-all whitespace-pre-wrap">{{ row.before }}</td>
          <td
            class="py-1 align-top break-all whitespace-pre-wrap"
            :class="row.changed ? 'font-semibold' : ''"
          >
            {{ row.after }}
          </td>
        </tr>
      </tbody>
    </table>

    <div v-if="hasContext">
      <p class="pb-1 font-medium text-ink-faint">Context</p>
      <pre class="overflow-x-auto rounded bg-canvas p-2 font-mono">{{
        JSON.stringify(context, null, 2)
      }}</pre>
    </div>

    <p v-if="rows.length === 0 && !hasContext" class="text-ink-faint">No payload recorded.</p>
  </div>
</template>
