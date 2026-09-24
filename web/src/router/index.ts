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
