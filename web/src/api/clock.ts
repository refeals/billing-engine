import { apiRequest } from './client'

// Field names mirror the API payload (snake_case) so types map 1:1 to the Rails docs.
export interface ClockState {
  now: string
}

export type TickReport = Record<string, number>

export interface AdvanceResult extends ClockState {
  ticks_run: number
  tick_report: TickReport
}

export function fetchClock(): Promise<ClockState> {
  return apiRequest('/simulator/clock')
}

export function advanceClock(days: number): Promise<AdvanceResult> {
  return apiRequest('/simulator/clock/advance', { method: 'POST', body: { days } })
}

export function resetClock(): Promise<ClockState> {
  return apiRequest('/simulator/clock/reset', { method: 'POST' })
}
