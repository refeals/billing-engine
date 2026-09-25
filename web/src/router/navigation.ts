export interface NavigationItem {
  label: string
  to: string
}

export interface NavigationGroup {
  label: string
  items: NavigationItem[]
}

export const navigation: NavigationGroup[] = [
  {
    label: 'Overview',
    items: [{ label: 'Dashboard', to: '/' }],
  },
  {
    label: 'Billing',
    items: [
      { label: 'Subscriptions', to: '/subscriptions' },
      { label: 'Customers', to: '/customers' },
      { label: 'Plans', to: '/plans' },
      { label: 'Invoices', to: '/invoices' },
    ],
  },
  {
    label: 'Operations',
    items: [
      { label: 'Dunning', to: '/dunning' },
      { label: 'Reconciliation', to: '/reconciliation' },
      { label: 'Webhook inbox', to: '/webhooks' },
      { label: 'Audit log', to: '/audit' },
    ],
  },
  {
    label: 'Simulator',
    items: [{ label: 'Scenario Lab', to: '/simulator' }],
  },
]
