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
      { label: 'Subscriptions', to: '/subscriptions', plan: '04', enabled: false },
      { label: 'Customers', to: '/customers', plan: '03', enabled: false },
      { label: 'Plans', to: '/plans', plan: '03', enabled: false },
      { label: 'Invoices', to: '/invoices', plan: '07', enabled: false },
    ],
  },
  {
    label: 'Operations',
    items: [
      { label: 'Dunning', to: '/dunning', plan: '10', enabled: false },
      { label: 'Reconciliation', to: '/reconciliation', plan: '11', enabled: false },
      { label: 'Audit log', to: '/audit', plan: '02', enabled: false },
    ],
  },
  {
    label: 'Simulator',
    items: [
      { label: 'Webhook inbox', to: '/webhooks', plan: '05', enabled: false },
      { label: 'Scenario Lab', to: '/simulator', plan: '06', enabled: false },
    ],
  },
]
