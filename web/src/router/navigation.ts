export interface NavigationItem {
  label: string
  to: string
  // The plan in docs/ that ships this section. Items stay visible but disabled until
  // then, so the sidebar doubles as a map of the whole product.
  plan: string
  enabled: boolean
}

export interface NavigationGroup {
  label: string
  items: NavigationItem[]
}

export const navigation: NavigationGroup[] = [
  {
    label: 'Overview',
    items: [{ label: 'Dashboard', to: '/', plan: '13', enabled: true }],
  },
  {
    label: 'Billing',
    items: [
      { label: 'Subscriptions', to: '/subscriptions', plan: '04', enabled: true },
      { label: 'Customers', to: '/customers', plan: '03', enabled: true },
      { label: 'Plans', to: '/plans', plan: '03', enabled: true },
      { label: 'Invoices', to: '/invoices', plan: '07', enabled: true },
    ],
  },
  {
    label: 'Operations',
    items: [
      { label: 'Dunning', to: '/dunning', plan: '10', enabled: true },
      { label: 'Reconciliation', to: '/reconciliation', plan: '11', enabled: true },
      { label: 'Webhook inbox', to: '/webhooks', plan: '05', enabled: true },
      { label: 'Audit log', to: '/audit', plan: '02', enabled: true },
    ],
  },
  {
    label: 'Simulator',
    items: [{ label: 'Scenario Lab', to: '/simulator', plan: '12', enabled: true }],
  },
]
