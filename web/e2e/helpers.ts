import { expect, type APIRequestContext } from '@playwright/test'

import { API_URL } from '../playwright.config'

// The `request` fixture carries the demo session cookie (storageState), so these helpers
// call the API as the signed-in operator. They build starting points; the specs exercise
// the UI.

async function call<T>(response: Promise<import('@playwright/test').APIResponse>): Promise<T> {
  const result = await response
  expect(result.ok(), `${result.url()} → ${result.status()} ${await result.text()}`).toBeTruthy()
  return (await result.json()) as T
}

// Back to the seeded demo: 20 studios, clock on 2026-03-16. Takes about 10 seconds.
export async function resetDemo(request: APIRequestContext) {
  await call(request.post(`${API_URL}/simulator/reset`, { data: { confirm: 'reset' }, timeout: 120_000 }))
}

let sequence = 0

// A new customer with a default test card, subscribed to a catalog plan. Unique names keep
// specs independent of each other and of the seeded studios.
export async function createSubscription(
  request: APIRequestContext,
  { plan = 'studio', card = 'pm_card_visa' }: { plan?: string; card?: string } = {},
) {
  sequence += 1
  const tag = `${Date.now().toString(36)}${sequence}`
  const customer = await call<{ id: number; name: string }>(
    request.post(`${API_URL}/customers`, {
      data: { name: `E2E Studio ${tag}`, email: `e2e-${tag}@studio.test` },
    }),
  )
  await call(
    request.post(`${API_URL}/customers/${customer.id}/payment_methods`, {
      data: { test_card: card, exp_month: 12, exp_year: 2030, default: true },
    }),
  )
  const plans = await call<{ data: { id: number; code: string }[] }>(request.get(`${API_URL}/plans`))
  const planId = plans.data.find((candidate) => candidate.code === plan)?.id
  if (!planId) throw new Error(`plan ${plan} not found`)

  const subscription = await call<{ id: number }>(
    request.post(`${API_URL}/subscriptions`, { data: { customer_id: customer.id, plan_id: planId } }),
  )
  return { customer, subscription }
}

// The newest paid invoice of a subscription (the first charge settles through the provider's
// webhook right after the request commits).
export async function paidInvoiceOf(request: APIRequestContext, subscriptionId: number) {
  await expect
    .poll(async () => {
      const invoices = await call<{ data: { id: number; status: string }[] }>(
        request.get(`${API_URL}/invoices?subscription_id=${subscriptionId}&status=paid`),
      )
      return invoices.data[0]?.id ?? null
    })
    .not.toBeNull()
  const invoices = await call<{ data: { id: number }[] }>(
    request.get(`${API_URL}/invoices?subscription_id=${subscriptionId}&status=paid`),
  )
  return invoices.data[0]!.id
}
