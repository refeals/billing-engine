<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute } from 'vue-router'

import { ApiError } from '@/api/client'
import { toApiError } from '@/api/errors'
import { keyAfterFailure, newIdempotencyKey } from '@/api/idempotency'
import { fetchInvoices } from '@/api/invoices'
import { cancelScheduledPlanChange, fetchPlanChanges } from '@/api/planChanges'
import {
  fetchStateTransitions,
  fetchSubscription,
  runSubscriptionAction,
} from '@/api/subscriptions'
import BaseBadge from '@/components/BaseBadge.vue'
import BaseButton from '@/components/BaseButton.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import InvoiceStatusBadge from '@/features/invoices/InvoiceStatusBadge.vue'
import { useAsyncData } from '@/composables/useAsyncData'
import { useClockRefresh } from '@/composables/useClockRefresh'
import { useClockStore } from '@/stores/clock'
import { formatDate, formatDateTime, formatMoney } from '@/utils/format'
import { humanize } from '@/utils/text'
import CancelSubscriptionDialog from './CancelSubscriptionDialog.vue'
import ChangePlanDialog from './ChangePlanDialog.vue'
import PauseSubscriptionDialog from './PauseSubscriptionDialog.vue'

type DialogName = 'cancel' | 'pause' | 'resume' | 'undo_cancel'

const route = useRoute()
const clock = useClockStore()
const subscriptionId = computed(() => String(route.params.id))

const subscriptionData = useAsyncData(() => fetchSubscription(subscriptionId.value))
const transitionsData = useAsyncData(() => fetchStateTransitions(subscriptionId.value))
const invoicesData = useAsyncData(() => fetchInvoices({ subscription_id: subscriptionId.value }))
const planChangesData = useAsyncData(() => fetchPlanChanges(subscriptionId.value))
const subscription = computed(() => subscriptionData.data.value)
const actions = computed(() => new Set(subscription.value?.allowed_actions ?? []))

function reloadAll() {
  subscriptionData.reload()
  transitionsData.reload()
  invoicesData.reload()
  planChangesData.reload()
}

useClockRefresh(reloadAll)
watch(subscriptionId, reloadAll)

const dialog = ref<DialogName | null>(null)
const pending = ref(false)
const actionError = ref<ApiError | null>(null)
let idempotencyKey = newIdempotencyKey()

function openDialog(name: DialogName) {
  // One key per attempt: a double click or retry inside this dialog is applied once.
  idempotencyKey = newIdempotencyKey()
  actionError.value = null
  dialog.value = name
}

function dialogModel(name: DialogName) {
  return computed({
    get: () => dialog.value === name,
    set: (open: boolean) => {
      if (!open) dialog.value = null
    },
  })
}
const cancelOpen = dialogModel('cancel')
const pauseOpen = dialogModel('pause')
const resumeOpen = dialogModel('resume')
const undoOpen = dialogModel('undo_cancel')

// A 409 means someone (or a tick) changed the subscription after this screen loaded; the
// safe move is to show the latest state rather than retry blindly.
const conflict = computed(() => actionError.value?.isConflict ?? false)
const dialogError = computed(() =>
  actionError.value && !conflict.value ? actionError.value.message : null,
)

async function run(
  endpoint: 'cancel' | 'undo_cancel' | 'pause' | 'resume',
  body: Record<string, unknown> = {},
) {
  if (!subscription.value) return
  pending.value = true
  actionError.value = null
  try {
    subscriptionData.data.value = await runSubscriptionAction(
      subscription.value,
      endpoint,
      idempotencyKey,
      body,
    )
    dialog.value = null
    transitionsData.reload()
    invoicesData.reload()
  } catch (caught) {
    actionError.value = toApiError(caught)
    idempotencyKey = keyAfterFailure(idempotencyKey, actionError.value)
    if (actionError.value.isConflict) dialog.value = null
  } finally {
    pending.value = false
  }
}

function reloadAfterConflict() {
  actionError.value = null
  reloadAll()
}

// The API needs a resume date strictly after now, and dates mean the start of the day
// (UTC), so the earliest valid choice is tomorrow in simulated time.
const changingPlan = ref(false)
const planChangeError = ref<string | null>(null)

function onPlanChanged() {
  reloadAll()
}

// A conflict means the subscription moved on (renewed, changed elsewhere): show the latest
// state and say nothing was applied, the same way the other actions do.
function onPlanChangeConflict() {
  actionError.value = new ApiError(409, 'stale', 'Changed elsewhere')
}

async function cancelScheduledChange() {
  const scheduled = subscription.value?.scheduled_plan_change
  if (!subscription.value || !scheduled) return
  planChangeError.value = null
  try {
    await cancelScheduledPlanChange(subscription.value.id, scheduled.id)
    reloadAll()
  } catch (caught) {
    planChangeError.value = toApiError(caught).message
  }
}

const tomorrow = computed(() => {
  const base = clock.now ? new Date(clock.now) : new Date()
  base.setUTCDate(base.getUTCDate() + 1)
  return base.toISOString().slice(0, 10)
})
</script>

<template>
  <div class="space-y-6">
    <RouterLink to="/subscriptions" class="text-sm text-accent hover:text-accent-strong">
      ← All subscriptions
    </RouterLink>

    <p v-if="subscriptionData.error.value" class="text-sm text-danger" role="alert">
      {{ subscriptionData.error.value.message }}
    </p>

    <div
      v-if="conflict"
      class="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-status-past-due/30 bg-status-past-due/5 px-4 py-3 text-sm"
      role="alert"
    >
      <span>This subscription changed after you opened it. Nothing was applied.</span>
      <BaseButton @click="reloadAfterConflict">Reload latest</BaseButton>
    </div>

    <template v-if="subscription">
      <header class="rounded-lg border border-border bg-surface p-5">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div class="flex items-center gap-3">
              <h2 class="text-lg font-semibold">{{ subscription.plan.name }}</h2>
              <StatusBadge :status="subscription.status" />
            </div>
            <p class="text-sm text-ink-muted">
              {{ formatMoney(subscription.plan.amount_cents) }} / {{ subscription.plan.interval }} ·
              <RouterLink
                :to="{ name: 'customer', params: { id: subscription.customer.id } }"
                class="text-accent hover:text-accent-strong"
              >
                {{ subscription.customer.name }}
              </RouterLink>
            </p>
            <p class="mt-2 font-mono text-xs text-ink-faint">
              {{ subscription.provider_subscription_id }}
            </p>
          </div>

          <div class="flex flex-wrap gap-2">
            <BaseButton
              v-if="actions.has('resume')"
              variant="primary"
              @click="openDialog('resume')"
            >
              Resume
            </BaseButton>
            <BaseButton
              v-if="actions.has('undo_cancel')"
              variant="primary"
              @click="openDialog('undo_cancel')"
            >
              Keep subscription
            </BaseButton>
            <BaseButton v-if="actions.has('change_plan')" @click="changingPlan = true">
              Change plan
            </BaseButton>
            <BaseButton v-if="actions.has('pause')" @click="openDialog('pause')">Pause</BaseButton>
            <BaseButton
              v-if="actions.has('cancel_now')"
              variant="danger"
              @click="openDialog('cancel')"
            >
              Cancel
            </BaseButton>
          </div>
        </div>

        <div
          v-if="subscription.scheduled_plan_change"
          class="mt-4 flex flex-wrap items-center justify-between gap-2 rounded-md bg-accent/5 px-3 py-2 text-sm"
        >
          <span>
            Switches to <strong>{{ subscription.scheduled_plan_change.to_plan.name }}</strong> on
            {{ formatDate(subscription.scheduled_plan_change.effective_at) }}.
          </span>
          <BaseButton variant="ghost" @click="cancelScheduledChange">Keep current plan</BaseButton>
          <p v-if="planChangeError" class="w-full text-danger" role="alert">
            {{ planChangeError }}
          </p>
        </div>
        <p
          v-if="subscription.cancel_at_period_end"
          class="mt-4 rounded-md bg-status-canceled/5 px-3 py-2 text-sm text-status-canceled"
        >
          Scheduled to cancel on {{ formatDate(subscription.current_period_end) }}.
        </p>
        <p
          v-else-if="subscription.status === 'paused'"
          class="mt-4 rounded-md bg-canvas px-3 py-2 text-sm text-ink-muted"
        >
          Paused since {{ formatDate(subscription.paused_at!) }}.
          {{
            subscription.resumes_at
              ? `Resumes on ${formatDate(subscription.resumes_at)}.`
              : 'Resumes when someone resumes it.'
          }}
        </p>
        <p
          v-else-if="subscription.status === 'canceled' && subscription.canceled_at"
          class="mt-4 rounded-md bg-canvas px-3 py-2 text-sm text-ink-muted"
        >
          Canceled on {{ formatDate(subscription.canceled_at) }} ({{
            humanize(subscription.cancellation_reason ?? 'unknown')
          }}).
        </p>

        <dl class="mt-4 grid gap-4 text-sm sm:grid-cols-3">
          <div>
            <dt class="text-xs text-ink-faint">
              {{ subscription.status === 'trialing' ? 'Trial period' : 'Current period' }}
            </dt>
            <dd>
              {{ formatDate(subscription.current_period_start) }} –
              {{ formatDate(subscription.current_period_end) }}
            </dd>
          </div>
          <div v-if="subscription.trial_ends_at">
            <dt class="text-xs text-ink-faint">Trial ends</dt>
            <dd>{{ formatDate(subscription.trial_ends_at) }}</dd>
          </div>
          <div>
            <dt class="text-xs text-ink-faint">Subscribed</dt>
            <dd>{{ formatDate(subscription.created_at) }}</dd>
          </div>
        </dl>
      </header>

      <div class="grid gap-6 lg:grid-cols-3">
        <section class="rounded-lg border border-border bg-surface lg:col-span-2">
          <h3 class="border-b border-border px-5 py-3 text-sm font-semibold">Invoices</h3>
          <table v-if="(invoicesData.data.value?.data.length ?? 0) > 0" class="w-full text-sm">
            <tbody>
              <tr
                v-for="invoice in invoicesData.data.value?.data ?? []"
                :key="invoice.id"
                class="border-b border-border last:border-b-0"
              >
                <td class="px-5 py-2">
                  <RouterLink
                    :to="{ name: 'invoice', params: { id: invoice.id } }"
                    class="font-mono hover:text-accent"
                  >
                    {{ invoice.number }}
                  </RouterLink>
                </td>
                <td class="px-5 py-2 text-ink-muted">
                  {{ formatDate(invoice.period_start) }} – {{ formatDate(invoice.period_end) }}
                </td>
                <td class="px-5 py-2 text-right tabular-nums">
                  {{ formatMoney(invoice.total_cents) }}
                </td>
                <td class="px-5 py-2 text-right">
                  <InvoiceStatusBadge :status="invoice.status" />
                </td>
              </tr>
            </tbody>
          </table>
          <p v-else class="px-5 py-4 text-sm text-ink-muted">
            {{
              subscription.status === 'trialing'
                ? 'No invoices yet: the first one is issued when the trial ends.'
                : 'No invoices yet.'
            }}
          </p>
        </section>

        <section class="rounded-lg border border-border bg-surface p-5">
          <h3 class="text-sm font-semibold">Card charged at renewal</h3>
          <template v-if="subscription.default_payment_method">
            <p class="mt-2 text-sm">
              {{ humanize(subscription.default_payment_method.brand) }} ····
              {{ subscription.default_payment_method.last4 }}
            </p>
            <p class="text-xs text-ink-muted">
              Expires
              {{ String(subscription.default_payment_method.exp_month).padStart(2, '0') }}/{{
                subscription.default_payment_method.exp_year
              }}
              · {{ humanize(subscription.default_payment_method.behavior) }}
            </p>
            <BaseBadge
              v-if="subscription.default_payment_method.expired"
              tone="danger"
              class="mt-2"
            >
              Expired
            </BaseBadge>
          </template>
          <p v-else class="mt-2 text-sm text-danger">No card on file: the next charge will fail.</p>
          <RouterLink
            :to="{ name: 'customer', params: { id: subscription.customer.id } }"
            class="mt-3 inline-block text-sm text-accent hover:text-accent-strong"
          >
            Manage cards →
          </RouterLink>
        </section>
      </div>

      <section
        v-if="(planChangesData.data.value?.data.length ?? 0) > 0"
        class="rounded-lg border border-border bg-surface"
      >
        <h3 class="border-b border-border px-5 py-3 text-sm font-semibold">Plan changes</h3>
        <table class="w-full text-sm">
          <tbody>
            <tr
              v-for="change in planChangesData.data.value?.data ?? []"
              :key="change.id"
              class="border-b border-border last:border-b-0"
            >
              <td class="px-5 py-2 text-ink-muted">{{ formatDate(change.effective_at) }}</td>
              <td class="px-5 py-2">{{ change.from_plan.name }} → {{ change.to_plan.name }}</td>
              <td class="px-5 py-2 text-ink-muted">{{ humanize(change.kind) }}</td>
              <td class="px-5 py-2 text-right tabular-nums">
                <RouterLink
                  v-if="change.invoice_id"
                  :to="{ name: 'invoice', params: { id: change.invoice_id } }"
                  class="text-accent hover:text-accent-strong"
                >
                  {{ formatMoney(change.net_cents) }}
                </RouterLink>
                <span v-else>{{
                  change.net_cents === 0 ? '—' : formatMoney(change.net_cents)
                }}</span>
              </td>
              <td class="px-5 py-2 text-right">
                <BaseBadge
                  :tone="
                    change.status === 'applied'
                      ? 'success'
                      : change.status === 'scheduled'
                        ? 'accent'
                        : 'neutral'
                  "
                >
                  {{ humanize(change.status) }}
                </BaseBadge>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <section class="rounded-lg border border-border bg-surface">
        <div class="flex items-center justify-between border-b border-border px-5 py-3">
          <h3 class="text-sm font-semibold">Status history</h3>
          <RouterLink
            :to="{ name: 'subscription-history', params: { id: subscription.id } }"
            class="text-sm text-accent hover:text-accent-strong"
          >
            Full audit history →
          </RouterLink>
        </div>
        <table class="w-full text-sm">
          <thead class="border-b border-border text-left text-xs text-ink-faint">
            <tr>
              <th class="px-5 py-2 font-medium">When</th>
              <th class="px-5 py-2 font-medium">Change</th>
              <th class="px-5 py-2 font-medium">Reason</th>
              <th class="px-5 py-2 font-medium">By</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="transition in transitionsData.data.value?.data ?? []"
              :key="transition.id"
              class="border-b border-border last:border-b-0"
            >
              <td class="px-5 py-2 text-ink-muted">{{ formatDateTime(transition.occurred_at) }}</td>
              <td class="px-5 py-2">
                <span class="text-ink-muted">{{
                  transition.from_status ? humanize(transition.from_status) : 'Created'
                }}</span>
                → <StatusBadge :status="transition.to_status" />
              </td>
              <td class="px-5 py-2">{{ humanize(transition.reason) }}</td>
              <td class="px-5 py-2 text-ink-muted">{{ humanize(transition.actor_type) }}</td>
            </tr>
          </tbody>
        </table>
      </section>

      <ChangePlanDialog
        v-model:open="changingPlan"
        :subscription="subscription"
        @changed="onPlanChanged"
        @conflict="onPlanChangeConflict"
      />
      <CancelSubscriptionDialog
        v-model:open="cancelOpen"
        :subscription="subscription"
        :pending="pending"
        :error="dialogError"
        @confirm="(atPeriodEnd) => run('cancel', { at_period_end: atPeriodEnd })"
      />
      <PauseSubscriptionDialog
        v-model:open="pauseOpen"
        :pending="pending"
        :error="dialogError"
        :min-date="tomorrow"
        @confirm="(resumesAt) => run('pause', resumesAt ? { resumes_at: resumesAt } : {})"
      />
      <ConfirmDialog
        v-model:open="resumeOpen"
        title="Resume subscription"
        confirm-label="Resume"
        variant="primary"
        :pending="pending"
        :error="dialogError"
        @confirm="run('resume')"
      >
        <p>The subscription becomes active again.</p>
      </ConfirmDialog>
      <ConfirmDialog
        v-model:open="undoOpen"
        title="Keep subscription"
        confirm-label="Keep subscription"
        variant="primary"
        :pending="pending"
        :error="dialogError"
        @confirm="run('undo_cancel')"
      >
        <p>The scheduled cancellation is removed and the subscription renews as usual.</p>
      </ConfirmDialog>
    </template>
  </div>
</template>
