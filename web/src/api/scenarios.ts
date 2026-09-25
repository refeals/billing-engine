import { apiRequest } from './client'
import { toQueryString } from './query'
import type { Paginated } from './types'

export interface Scenario {
  key: string
  title: string
  description: string
}

export interface ScenarioLogEntry {
  step: string
  detail?: string
  // Simulated time the step ran at.
  at: string
}

export interface ScenarioRun {
  id: number
  scenario_key: string
  title: string
  status: 'running' | 'passed' | 'failed'
  error: string | null
  log: ScenarioLogEntry[]
  customer_id: number | null
  subscription_id: number | null
  started_at: string
  finished_at: string | null
}

export interface DemoSummary {
  simulated_now: string
  customers: number
  subscriptions: Record<string, number>
  invoices: Record<string, number>
  open_dunning_cases: Record<string, number>
  refunds: Record<string, number>
  customers_with_credit: number
  open_discrepancies: number
}

// Checks are the steps a scenario asserts; the API marks them with a leading check mark.
export function isCheck(entry: ScenarioLogEntry): boolean {
  return entry.step.startsWith('✓')
}

export function fetchScenarios() {
  return apiRequest<{ data: Scenario[] }>('/simulator/scenarios')
}

export function runScenario(key: string) {
  return apiRequest<ScenarioRun>(`/simulator/scenarios/${encodeURIComponent(key)}/run`, {
    method: 'POST',
  })
}

export function fetchScenarioRuns(options: { page?: number } = {}) {
  return apiRequest<Paginated<ScenarioRun>>(`/simulator/scenarios/runs${toQueryString(options)}`)
}

// The API refuses a reset unless the request spells out the confirmation.
export function resetDemoData() {
  return apiRequest<DemoSummary>('/simulator/reset', {
    method: 'POST',
    body: { confirm: 'reset' },
  })
}
