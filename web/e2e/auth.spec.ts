import { expect, test } from '@playwright/test'

// Starts signed out: every other spec reuses the saved demo session.
test.use({ storageState: { cookies: [], origins: [] } })

test('a signed-out visitor signs in with the demo credentials and signs out', async ({ page }) => {
  await page.goto('/subscriptions?status=active')
  await expect(page).toHaveURL(/\/login\?redirect=/)
  await expect(page.getByRole('heading', { name: 'Demo credentials' })).toBeVisible()

  await page.getByLabel('Email').fill('demo@billing-engine.dev')
  await page.getByLabel('Password').fill('not-the-password')
  await page.getByRole('button', { name: 'Sign in' }).click()
  await expect(page.getByRole('alert')).toHaveText('Wrong email or password')

  await page.getByRole('button', { name: 'Use demo credentials' }).click()
  await page.getByRole('button', { name: 'Sign in' }).click()

  // Back where the visitor wanted to go, with the filter kept.
  await expect(page).toHaveURL(/\/subscriptions\?status=active$/)
  await expect(page.getByRole('heading', { name: 'Subscriptions', level: 1 })).toBeVisible()

  await page.reload()
  await expect(page.getByText('demo@billing-engine.dev')).toBeVisible()

  await page.getByRole('button', { name: 'Sign out' }).click()
  await expect(page).toHaveURL(/\/login$/)

  await page.goto('/invoices')
  await expect(page).toHaveURL(/\/login\?redirect=%2Finvoices|\/login\?redirect=\/invoices/)
})
