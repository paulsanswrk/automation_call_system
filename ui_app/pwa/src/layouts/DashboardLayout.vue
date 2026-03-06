<template>
  <div class="dashboard dark-mode" :class="{ 'sidebar-closed': !isSidebarOpen }">
    <aside class="sidebar" :class="{ 'closed': !isSidebarOpen }">
      <div class="sidebar-brand">
        <h2><span class="pi pi-chart-bar" style="margin-right: 0.5rem; font-size: 1.2rem"></span>ACT Trading</h2>
        <span class="brand-subtitle">Algorithmic Crypto Trading</span>
      </div>

      <nav class="sidebar-nav">
        <router-link to="/" class="nav-item" active-class="none" exact-active-class="router-link-active">
          <span class="nav-icon pi pi-bell"></span>
          Notifications
          <span v-if="unreadNotificationsCount > 0" style="background: var(--amber-badge); color: #000; padding: 2px 6px; border-radius: 12px; font-size: 0.75rem; font-weight: bold; margin-left: auto;">
            {{ unreadNotificationsCount }}
          </span>
        </router-link>
        <router-link to="/positions" class="nav-item">
          <span class="nav-icon pi pi-chart-line"></span>
          Positions
        </router-link>
        <router-link to="/exchange-accounts" class="nav-item">
          <span class="nav-icon pi pi-wallet"></span>
          Exchanges
        </router-link>
        <router-link to="/channels" class="nav-item" v-if="isAdmin">
          <span class="nav-icon pi pi-hashtag"></span>
          Channels
        </router-link>
        <router-link to="/trade-actions" class="nav-item" v-if="isAdmin">
          <span class="nav-icon pi pi-list"></span>
          Trade Actions
        </router-link>
        <router-link to="/ai-log" class="nav-item" v-if="isAdmin">
          <span class="nav-icon pi pi-file"></span>
          AI Log
        </router-link>
        <router-link to="/orders" class="nav-item">
          <span class="nav-icon pi pi-list"></span>
          Position Helper
        </router-link>

      </nav>

      <div class="sidebar-footer">
        <button
          v-if="pushSupported"
          class="nav-item push-toggle"
          :class="{ 'push-active': pushSubscribed }"
          @click="togglePush"
          :disabled="pushLoading"
        >
          <span class="nav-icon pi pi-bell"></span>
          <span v-if="pushLoading">Working…</span>
          <span v-else-if="pushSubscribed">
            <span class="push-on-dot"></span>
            Notifications On
          </span>
          <span v-else>Enable Notifications</span>
        </button>
        <div class="user-info">
          <div class="user-avatar">
            <img v-if="user?.user_metadata?.avatar_url" :src="user.user_metadata.avatar_url" alt="Avatar" />
            <span v-else>{{ userInitial }}</span>
          </div>
          <span class="user-name">{{ userName }}</span>
        </div>
        <button class="nav-item" @click="handleSignOut">
          <span class="nav-icon pi pi-sign-out"></span>
          Sign Out
        </button>
      </div>
    </aside>

    <main class="main-content" :class="{ 'expanded': !isSidebarOpen }">
      <div class="top-bar">
        <div class="top-bar-left">
          <button class="sidebar-toggle-btn" @click="toggleSidebar" title="Toggle Sidebar">
            <span class="pi pi-bars"></span>
          </button>
          <h1 class="page-title">{{ $route.meta.title || $route.name }}</h1>
        </div>
        <div class="top-bar-controls">
          <div class="build-info" :class="{ 'has-update': needRefresh || updateAvailable }">
            <span class="version">v{{ appVersion }}</span>
            <span v-if="updateAvailable" class="version" style="margin-left: 0.25rem;">({{ updateAvailable }})</span>
            <span v-if="needRefresh || updateAvailable" class="pi pi-exclamation-triangle warning-icon" title="Update Available"></span>
          </div>
          <button class="refresh-btn" @click="handleRefresh" title="Refresh App">
            <span class="pi pi-refresh" :class="{ 'pi-spin': isRefreshing }"></span>
          </button>
        </div>
      </div>

      <router-view />
    </main>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '@/composables/useAuth'
import { usePushNotifications } from '@/composables/usePushNotifications'
import { useSystemWS } from '@/composables/useSystemWS'
import { useRegisterSW } from 'virtual:pwa-register/vue'

const isSidebarOpen = ref(true)

function toggleSidebar() {
  isSidebarOpen.value = !isSidebarOpen.value
}

const appVersion = __APP_VERSION__
const { needRefresh, updateServiceWorker } = useRegisterSW()
const isRefreshing = ref(false)

const { connectSystemWebSocket, disconnect: disconnectWS, unreadNotificationsCount, updateAvailable } = useSystemWS()

onMounted(() => {
  connectSystemWebSocket()
})

onUnmounted(() => {
  disconnectWS()
})

async function handleRefresh() {
  isRefreshing.value = true
  if (needRefresh.value) {
    await updateServiceWorker(true)
  } else {
    window.location.reload()
  }
}

const router = useRouter()
const { user, signOut } = useAuth()
const {
  isSupported: pushSupported,
  isSubscribed: pushSubscribed,
  isLoading: pushLoading,
  toggleSubscription: togglePush,
} = usePushNotifications()

const isAdmin = computed(() => {
  return (user.value?.app_metadata as any)?.role === 'admin'
})

const userName = computed(() => {
  return user.value?.user_metadata?.full_name
    || user.value?.email
    || 'User'
})

const userInitial = computed(() => {
  return userName.value.charAt(0).toUpperCase()
})

async function handleSignOut() {
  await signOut()
  router.push('/login')
}
</script>

<style scoped>
.top-bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 1rem;
  margin-bottom: 1.5rem;
  padding-bottom: 0.75rem;
  border-bottom: 1px solid var(--surface-border);
}

.top-bar-left {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.sidebar-toggle-btn {
  background: transparent;
  border: none;
  color: var(--text-color);
  font-size: 1.25rem;
  cursor: pointer;
  padding: 0.25rem;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: color 0.2s;
  border-radius: 4px;
}

.sidebar-toggle-btn:hover {
  color: var(--primary-color);
  background: rgba(99, 102, 241, 0.1);
}

.top-bar-controls {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.page-title {
  font-size: 1.65rem;
  font-weight: 700;
  margin: 0;
  color: var(--text-color);
}

.build-info {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.75rem;
  color: var(--text-color-secondary);
  background: var(--surface-card);
  padding: 0.35rem 0.75rem;
  border-radius: 12px;
  border: 1px solid var(--surface-border);
  font-family: 'JetBrains Mono', monospace;
}

.build-info.has-update {
  color: #fbbf24;
  border-color: rgba(251, 191, 36, 0.4);
  background: rgba(251, 191, 36, 0.15);
}

.warning-icon {
  font-size: 0.8rem;
  animation: pulse 2s infinite;
}

.refresh-btn {
  background: var(--surface-card);
  border: 1px solid var(--surface-border);
  color: var(--text-color);
  width: 32px;
  height: 32px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: all 0.2s;
}

.refresh-btn:hover {
  background: rgba(99, 102, 241, 0.1);
  color: var(--primary-color);
  border-color: rgba(99, 102, 241, 0.3);
}

@media (max-width: 768px) {
  .top-bar {
    margin-bottom: 1rem;
    padding-bottom: 0.5rem;
  }
  
  .sidebar-toggle-btn {
    display: none;
  }
}
</style>
