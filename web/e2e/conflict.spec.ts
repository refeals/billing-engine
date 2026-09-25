import { expect, test } from '@playwright/test'

import { createSubscription } from './helpers'

test('a second operator acting on an old screen gets a conflict, not an overwrite', async ({ browser, request }) => {
  const { subscription } = await createSubscription(request)
  const context = await browser.newContext({ storageState: 'e2e/.auth/demo.json' })
  const first = await context.newPage()
  const second = await context.newPage()
  await first.goto(`/subscriptions/${subscription.id}`)
  await second.goto(`/subscriptions/${subscription.id}`)

  await first.getByRole('button', { name: 'Cancel', exact: true }).click()
  await first.getByLabel(/At the end of the period/).check()
  await first.getByRole('button', { name: 'Schedule cancellation' }).click()
  await expect(first.getByText(/Scheduled to cancel on/)).toBeVisible()

  // The second screen still shows the subscription before the cancellation was scheduled.
  await second.getByRole('button', { name: 'Pause' }).click()
  await second.getByRole('button', { name: 'Pause subscription' }).click()
  await expect(second.getByText('This subscription changed after you opened it. Nothing was applied.')).toBeVisible()

  await second.getByRole('button', { name: 'Reload latest' }).click()
  await expect(second.getByText(/Scheduled to cancel on/)).toBeVisible()
  await expect(second.getByRole('button', { name: 'Pause' })).toBeHidden()

  await context.close()
})
