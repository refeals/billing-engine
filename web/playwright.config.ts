import { defineConfig, devices } from '@playwright/test'

// One shared simulated clock and database: tests run one at a time, against a real API
// (test environment, its own SQLite file) and the production build of the web app.
export const API_URL = 'http://localhost:3100/api/v1'
const WEB_URL = 'http://localhost:4174'

export default defineConfig({
  testDir: 'e2e',
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  forbidOnly: !!process.env.CI,
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : 'list',
  globalSetup: './e2e/global-setup.ts',
  use: {
    baseURL: WEB_URL,
    storageState: 'e2e/.auth/demo.json',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: [
    {
      command: './e2e/start-api.sh',
      url: 'http://localhost:3100/up',
      timeout: 120_000,
      reuseExistingServer: !process.env.CI,
    },
    {
      command: `VITE_API_URL=${API_URL} pnpm build-only --outDir dist-e2e && pnpm exec vite preview --outDir dist-e2e --port 4174 --strictPort`,
      url: WEB_URL,
      timeout: 120_000,
      reuseExistingServer: !process.env.CI,
    },
  ],
})
