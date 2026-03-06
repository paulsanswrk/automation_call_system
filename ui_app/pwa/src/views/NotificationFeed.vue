<template>
  <div>
    <div class="feed-header">
      <div class="live-badge" v-if="isConnected">
        <span class="live-dot"></span>
        Live
      </div>
    </div>

    <!-- Filter Bar -->
    <div class="filter-row">
      <select v-model="filterChannel" class="setting-input filter-input action-select" @change="applyFilter">
        <option value="">All Channels</option>
        <option v-for="ch in channels" :key="ch.id" :value="ch.channel_name">#{{ch.channel_name}}</option>
      </select>
      <button @click="applyFilter" class="btn" :disabled="loading">Filter</button>
      <div style="flex: 1"></div>
      <button @click="bulkDelete" class="btn btn-danger" :disabled="loading || !filterChannel">
        <span class="pi pi-trash" style="margin-right:0.3rem"></span> Delete All
      </button>
    </div>

    <div v-if="loading" class="empty-state">
      <div class="spinner" style="margin: 0 auto;"></div>
    </div>

    <div v-else-if="messages.length === 0" class="empty-state">
      <div class="empty-icon pi pi-inbox"></div>
      <h2>No messages yet</h2>
      <p>Discord trade calls will appear here when they arrive.</p>
    </div>

    <div v-else class="message-list">
      <div
        v-for="msg in messages"
        :key="msg.id"
        class="message-card"
        :class="{ 'new-message': newMessageIds.has(msg.id) }"
        @click="selectedMessage = msg"
      >
        <div class="message-meta">
          <span class="message-author">{{ msg.author }}</span>
          <span class="message-channel">#{{ msg.channel_name }}</span>
          <span>{{ formatTime(msg.received_at) }}</span>
        </div>
        <div class="message-text message-text-truncated">
          {{ msg.text_content }}
        </div>
        <div class="trade-actions-row" v-if="tradeActionsByMsg[msg.message_id]?.length">
          <span
            v-for="action in tradeActionsByMsg[msg.message_id]"
            :key="action.id"
            class="action-badge"
            :class="{
              'place-order': action.action === 'PLACE_ORDER',
              'skip': action.action === 'SKIP',
              'error': action.action === 'ERROR',
            }"
          >
            {{ action.action }}
            <template v-if="action.symbol"> · {{ action.symbol }}</template>
            <template v-if="action.side"> {{ action.side }}</template>
          </span>
        </div>
      </div>
    </div>

    <!-- Detail Modal -->
    <div v-if="selectedMessage" class="detail-overlay" @click.self="selectedMessage = null">
      <div class="detail-panel">
        <button class="detail-close" @click="selectedMessage = null">✕</button>

        <div class="detail-section">
          <h3>Discord Message</h3>
          <table class="detail-table">
            <tr><td>Author</td><td>{{ selectedMessage.author }}</td></tr>
            <tr><td>Channel</td><td>#{{ selectedMessage.channel_name }}</td></tr>
            <tr><td>Time</td><td>{{ formatTimeFull(selectedMessage.received_at) }}</td></tr>
          </table>
          <div style="margin-top: 1rem; font-size: 0.9rem; line-height: 1.6; white-space: pre-wrap;">{{ selectedMessage.text_content }}</div>
        </div>

        <div class="detail-section" v-if="tradeActionsByMsg[selectedMessage.message_id]?.length">
          <h3>Trade Actions</h3>
          <div v-for="action in tradeActionsByMsg[selectedMessage.message_id]" :key="action.id" style="margin-bottom: 1rem;">
            <table class="detail-table">
              <tr><td>Action</td><td><span class="action-badge" :class="{
                'place-order': action.action === 'PLACE_ORDER',
                'skip': action.action === 'SKIP',
                'error': action.action === 'ERROR',
              }">{{ action.action }}</span></td></tr>
              <tr v-if="action.exchange"><td>Exchange</td><td>{{ action.exchange }}</td></tr>
              <tr v-if="action.symbol"><td>Symbol</td><td>{{ action.symbol }}</td></tr>
              <tr v-if="action.side"><td>Side</td><td>{{ action.side }}</td></tr>
              <tr v-if="action.order_type"><td>Order Type</td><td>{{ action.order_type }}</td></tr>
              <tr v-if="action.price"><td>Price</td><td>{{ action.price }}</td></tr>
              <tr v-if="action.qty"><td>Qty</td><td>{{ action.qty }}</td></tr>
              <tr v-if="action.sl_price"><td>Stop Loss</td><td>{{ action.sl_price }}</td></tr>
              <tr v-if="action.order_id"><td>Order ID</td><td style="font-family: monospace; font-size: 0.8rem;">{{ action.order_id }}</td></tr>
              <tr v-if="action.notes"><td>Notes</td><td>{{ action.notes }}</td></tr>
            </table>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted, onUnmounted, computed, watch } from 'vue'
import { apiFetch } from '@/lib/api'
import { useSystemWS } from '@/composables/useSystemWS'

interface DiscordMessage {
  id: number
  message_id: string
  author: string
  channel_name: string
  text_content: string
  received_at: string
  is_test: boolean
}

interface TradeAction {
  id: number
  discord_message_id: string
  action: string
  exchange: string
  symbol: string
  side: string
  order_type: string
  qty: string
  price: string
  order_id: string
  sl_price: string
  notes: string
}

interface Channel {
  id: number
  channel_name: string
}

const messages = ref<DiscordMessage[]>([])
const tradeActions = ref<TradeAction[]>([])
const channels = ref<Channel[]>([])
const loading = ref(true)
const selectedMessage = ref<DiscordMessage | null>(null)
const newMessageIds = reactive(new Set<number>())

const filterChannel = ref('')

const { isConnected, latestDiscordMessage, latestTradeAction, resetUnreadNotifications } = useSystemWS()

const tradeActionsByMsg = computed(() => {
  const map: Record<string, TradeAction[]> = {}
  for (const action of tradeActions.value) {
    if (!action.discord_message_id) continue
    if (!map[action.discord_message_id]) map[action.discord_message_id] = []
    map[action.discord_message_id].push(action)
  }
  return map
})

onMounted(async () => {
  await fetchData()
  resetUnreadNotifications() // clear notification badges when visiting this page
})

watch(latestDiscordMessage, (newMsg) => {
  if (newMsg) {
    if (!filterChannel.value || newMsg.channel_name === filterChannel.value) {
      messages.value.unshift(newMsg)
      newMessageIds.add(newMsg.id)
      setTimeout(() => newMessageIds.delete(newMsg.id), 3000)
    }
  }
})

watch(latestTradeAction, (newAction) => {
  if (newAction) {
    tradeActions.value.push(newAction)
  }
})

onUnmounted(() => {
  resetUnreadNotifications()
})

async function fetchData() {
  loading.value = true
  try {
    let msgUrl = '/api/messages'
    if (filterChannel.value) {
      msgUrl += `?channel_name=${encodeURIComponent(filterChannel.value)}`
    }
    const [msgRes, actionsRes, channelsRes] = await Promise.all([
      apiFetch(msgUrl),
      apiFetch('/api/trade-actions'),
      apiFetch('/api/channels')
    ])
    if (msgRes.ok) messages.value = await msgRes.json()
    if (actionsRes.ok) {
        const json = await actionsRes.json()
        tradeActions.value = json.data || []
    }
    if (channelsRes.ok) channels.value = await channelsRes.json()
  } catch (err) {
    console.error('Failed to fetch from Go API:', err)
  } finally {
    loading.value = false
  }
}

async function applyFilter() {
  messages.value = []
  await fetchData()
}

async function bulkDelete() {
  if (!filterChannel.value) {
    alert("Please enter a channel filter to enable bulk delete.")
    return
  }
  if (!confirm(`Are you sure you want to delete ALL messages matching channel "#${filterChannel.value}"?\nThis cannot be undone.`)) {
    return
  }
  
  loading.value = true
  try {
    const res = await apiFetch(`/api/messages?channel_name=${encodeURIComponent(filterChannel.value)}`, { method: 'DELETE' })
    if (res.ok) {
      const data = await res.json()
      alert(`Deleted ${data.count} messages.`)
      await fetchData()
    } else {
      const err = await res.json()
      alert("Delete failed: " + err.error)
    }
  } catch (e) {
    console.error(e)
    alert("Failed to delete messages.")
  } finally {
    loading.value = false
  }
}

function formatTime(dateStr: string) {
  const d = new Date(dateStr)
  const now = new Date()
  const diffMs = now.getTime() - d.getTime()
  const diffMins = Math.floor(diffMs / 60000)
  if (diffMins < 1) return 'just now'
  if (diffMins < 60) return `${diffMins}m ago`
  const diffHours = Math.floor(diffMins / 60)
  if (diffHours < 24) return `${diffHours}h ago`
  return d.toLocaleDateString()
}

function formatTimeFull(dateStr: string) {
  return new Date(dateStr).toLocaleString()
}
</script>

<style scoped>
.filter-row {
  display: flex;
  gap: 0.5rem;
  margin-bottom: 1.5rem;
  align-items: center;
}

.setting-input.filter-input {
  max-width: 250px;
  background: var(--surface-card);
  padding: 0.45rem 0.75rem;
  border-radius: 8px;
  border: 1px solid var(--surface-border);
  color: var(--text-color);
  font-size: 0.85rem;
}

.action-select {
  cursor: pointer;
}

.btn {
  background: var(--surface-card);
  border: 1px solid var(--surface-border);
  color: var(--text-color);
  padding: 0.45rem 1rem;
  border-radius: 8px;
  cursor: pointer;
  font-size: 0.85rem;
  font-weight: 500;
  transition: all 0.2s;
}

.btn:hover:not(:disabled) {
  border-color: var(--primary-color);
  background: rgba(99, 102, 241, 0.1);
  color: var(--primary-color);
}

.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn-danger {
  color: var(--red-badge);
}

.btn-danger:hover:not(:disabled) {
  border-color: var(--red-badge);
  background: rgba(239, 68, 68, 0.1);
}
</style>
