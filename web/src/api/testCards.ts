import { apiRequest } from './client'

export interface TestCard {
  token: string
  brand: string
  last4: string
  behavior: string
  description: string
}

export function fetchTestCards() {
  return apiRequest<{ data: TestCard[] }>('/simulator/test_cards')
}
