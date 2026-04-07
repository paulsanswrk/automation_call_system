<template>
  <div class="dashboard" :class="{ 'sidebar-closed': !isSidebarOpen }">
    <aside class="sidebar" :class="{ 'closed': !isSidebarOpen }">
      <div class="sidebar-brand">
        <h2>📊 ACT Trading</h2>
        <span class="brand-subtitle">Algorithmic Crypto Trading</span>
      </div>

      <nav class="sidebar-nav">
        <router-link to="/" class="nav-item" active-class="none" exact-active-class="router-link-active">
          <span class="nav-icon">🔔</span>
          Notifications
          <span v-if="unreadNotificationsCount > 0" class="notif-badge">
            {{ unreadNotificationsCount }}
          </span>
        </router-link>
        <router-link to="/positions" class="nav-item">
          <span class="nav-icon">📈</span>
          Positions
        </router-link>
        <router-link to="/exchange-accounts" class="nav-item">
          <span class="nav-icon">💼</span>
          Exchanges
        </router-link>
        <router-link to="/channels" class="nav-item" v-if="isAdmin">
          <span class="nav-icon">#️⃣</span>
          Channels
        </router-link>
        <router-link to="/trade-actions" class="nav-item" v-if="isAdmin">
          <span class="nav-icon">📋</span>
          Trade Actions
        </router-link>
        <router-link to="/ai-log" class="nav-item" v-if="isAdmin">
          <span class="nav-icon">🤖</span>
          AI Log
        </router-link>
      </nav>

      <div class="sidebar-footer">
        <div class="user-info">
          <div class="user-avatar">
            <img v-if="user?.user_metadata?.avatar_url" :src="user.user_metadata.avatar_url" alt="Avatar" />
            <span v-else>{{ userInitial }}</span>
          </div>
          <span class="user-name">{{ userName }}</span>
        </div>
        <button class="nav-item" @click="handleSignOut">
          <span class="nav-icon">🚪</span>
          Sign Out
        </button>
      </div>
    </aside>

    <main class="main-content" :class="{ 'expanded': !isSidebarOpen }">
      <div class="top-bar">
        <div class="top-bar-left">
          <button class="sidebar-toggle-btn" @click="toggleSidebar" title="Toggle Sidebar">
            ☰
          </button>
          <h1 class="page-title">{{ $route.meta.title || $route.name }}</h1>
        </div>
        <div class="top-bar-controls">
          <div class="connection-indicator" :class="isConnected ? 'conn-ok' : 'conn-off'" :title="isConnected ? 'Connected' : 'Disconnected'">
            <span class="conn-dot"></span>
            {{ isConnected ? 'Live' : 'Offline' }}
          </div>
          <div class="build-info">
            <span class="version">v{{ appVersion }}</span>
          </div>
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
import { useSystemWS } from '@/composables/useSystemWS'

const isSidebarOpen = ref(true)

function toggleSidebar() {
  isSidebarOpen.value = !isSidebarOpen.value
}

const appVersion = __APP_VERSION__

const { connectSystemWebSocket, disconnect: disconnectWS, unreadNotificationsCount, isConnected } = useSystemWS()

onMounted(() => {
  connectSystemWebSocket()
})

onUnmounted(() => {
  disconnectWS()
})

const router = useRouter()
const { user, signOut } = useAuth()

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
  padding: 0.25rem 0.4rem;
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

.connection-indicator {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.75rem;
  font-weight: 600;
  padding: 0.35rem 0.75rem;
  border-radius: 100px;
}

.connection-indicator.conn-ok {
  background: rgba(34, 197, 94, 0.1);
  border: 1px solid rgba(34, 197, 94, 0.3);
  color: var(--green-badge);
}

.connection-indicator.conn-off {
  background: rgba(239, 68, 68, 0.1);
  border: 1px solid rgba(239, 68, 68, 0.3);
  color: var(--red-badge);
}

.conn-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: currentColor;
  animation: pulse 2s infinite;
}

.notif-badge {
  background: var(--amber-badge);
  color: #000;
  padding: 2px 6px;
  border-radius: 12px;
  font-size: 0.75rem;
  font-weight: bold;
  margin-left: auto;
}
</style>
