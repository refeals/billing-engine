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
