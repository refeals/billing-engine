import { createRouter, createWebHistory } from 'vue-router'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'dashboard',
      component: () => import('@/features/dashboard/DashboardView.vue'),
      meta: { title: 'Dashboard' },
    },
    {
      path: '/subscriptions',
      name: 'subscriptions',
      component: () => import('@/features/subscriptions/SubscriptionsView.vue'),
      meta: { title: 'Subscriptions' },
    },
    {
      path: '/subscriptions/:id',
      name: 'subscription',
      component: () => import('@/features/subscriptions/SubscriptionDetailView.vue'),
      meta: { title: 'Subscription' },
    },
    {
      path: '/subscriptions/:id/history',
      name: 'subscription-history',
      component: () => import('@/features/subscriptions/SubscriptionHistoryView.vue'),
      meta: { title: 'Subscription history' },
    },
    {
      path: '/invoices',
      name: 'invoices',
      component: () => import('@/features/invoices/InvoicesView.vue'),
      meta: { title: 'Invoices' },
    },
    {
      path: '/invoices/:id',
      name: 'invoice',
      component: () => import('@/features/invoices/InvoiceDetailView.vue'),
      meta: { title: 'Invoice' },
    },
    {
      path: '/plans',
      name: 'plans',
      component: () => import('@/features/plans/PlansView.vue'),
      meta: { title: 'Plans' },
    },
    {
      path: '/customers',
      name: 'customers',
      component: () => import('@/features/customers/CustomersView.vue'),
      meta: { title: 'Customers' },
    },
    {
      path: '/customers/:id',
      name: 'customer',
      component: () => import('@/features/customers/CustomerDetailView.vue'),
      meta: { title: 'Customer' },
    },
    {
      path: '/dunning',
      name: 'dunning',
      component: () => import('@/features/dunning/DunningBoardView.vue'),
      meta: { title: 'Dunning' },
    },
    {
      path: '/reconciliation',
      name: 'reconciliation',
      component: () => import('@/features/reconciliation/ReconciliationView.vue'),
      meta: { title: 'Reconciliation' },
    },
    {
      path: '/webhooks',
      name: 'webhooks',
      component: () => import('@/features/webhooks/WebhookInboxView.vue'),
      meta: { title: 'Webhook inbox' },
    },
    {
      path: '/webhooks/:id',
      name: 'webhook-event',
      component: () => import('@/features/webhooks/WebhookEventDetailView.vue'),
      meta: { title: 'Webhook event' },
    },
    {
      path: '/simulator',
      name: 'scenario-lab',
      component: () => import('@/features/simulator/ScenarioLabView.vue'),
      meta: { title: 'Scenario Lab' },
    },
    {
      path: '/audit',
      name: 'audit-log',
      component: () => import('@/features/audit/AuditLogView.vue'),
      meta: { title: 'Audit log' },
    },
  ],
})

export default router

declare module 'vue-router' {
  interface RouteMeta {
    title?: string
  }
}
