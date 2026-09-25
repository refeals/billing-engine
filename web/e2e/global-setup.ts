import { mkdirSync } from 'node:fs'
import { dirname } from 'node:path'

import { request, type FullConfig } from '@playwright/test'

import { DEMO_CREDENTIALS } from '../src/api/demoCredentials'
import { API_URL } from '../playwright.config'

export const AUTH_FILE = 'e2e/.auth/demo.json'

// Signs in once through the API and resets the demo to its seeded state (clock on
// 2026-03-16). Specs start from the saved cookie instead of each typing the password; the
// reset keeps sessions, so the cookie stays valid when a spec resets again.
export default async function globalSetup(_config: FullConfig) {
  const api = await request.newContext({ baseURL: `${API_URL}/` })

  const signIn = await api.post('session', { data: DEMO_CREDENTIALS })
  if (signIn.status() !== 201) throw new Error(`demo sign-in failed: ${signIn.status()}`)

  const reset = await api.post('simulator/reset', { data: { confirm: 'reset' }, timeout: 120_000 })
  if (!reset.ok()) throw new Error(`demo reset failed: ${reset.status()}`)

  mkdirSync(dirname(AUTH_FILE), { recursive: true })
  await api.storageState({ path: AUTH_FILE })
  await api.dispose()
}
