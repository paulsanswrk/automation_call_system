import { createRouter, createWebHistory } from 'vue-router'
import { supabase } from '@/lib/supabase'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'Login',
      component: () => import('@/views/LoginPage.vue'),
      meta: { requiresAuth: false },
    },
    {
      path: '/',
      component: () => import('@/layouts/DashboardLayout.vue'),
      meta: { requiresAuth: true },
      children: [
        {
          path: '',
          name: 'Notifications',
          component: () => import('@/views/NotificationFeed.vue'),
          meta: { title: 'Notifications' },
        },
        {
          path: 'positions',
          name: 'Positions',
          component: () => import('@/views/PositionsView.vue'),
          meta: { title: 'Open Positions' },
        },
        {
          path: 'exchange-accounts',
          name: 'ExchangeAccounts',
          component: () => import('@/views/ExchangeAccountsView.vue'),
          meta: { title: 'Exchange Accounts' },
        },
        {
          path: 'channels',
          name: 'Channels',
          component: () => import('@/views/ChannelsView.vue'),
          meta: { requiresAdmin: true, title: 'Channels' },
        },
        {
          path: 'trade-actions',
          name: 'TradeActions',
          component: () => import('@/views/TradeActionsView.vue'),
          meta: { requiresAdmin: true, title: 'Trade Actions' },
        },
        {
          path: 'ai-log',
          name: 'AILog',
          component: () => import('@/views/AILogView.vue'),
          meta: { requiresAdmin: true, title: 'AI Logs' },
        },
        {
          path: 'orders',
          name: 'Orders',
          component: () => import('@/views/PlaceholderView.vue'),
          meta: { title: 'Position Helper' },
        },
      ],
    },
  ],
})

router.beforeEach(async (to) => {
  const { data } = await supabase.auth.getSession()
  const isAuthenticated = !!data.session
  const isAdmin = (data.session?.user?.app_metadata as any)?.role === 'admin'

  if (to.meta.requiresAuth && !isAuthenticated) {
    return { name: 'Login' }
  }
  
  if (to.meta.requiresAdmin && !isAdmin) {
    return { path: '/positions' }
  }

  if (to.name === 'Login' && isAuthenticated) {
    return { path: '/' }
  }
})

export default router
