<template>
  <div>




    <!-- Loading -->
    <div v-if="loading && channels.length === 0" class="empty-state">
      <div class="spinner" style="margin: 0 auto;"></div>
    </div>

    <!-- Empty -->
    <div v-else-if="channels.length === 0" class="empty-state">
      <div class="empty-icon pi pi-hashtag"></div>
      <h2>No Channels Yet</h2>
      <p>Channels appear automatically when Discord messages arrive, or add one manually.</p>
    </div>

    <!-- Channels Grid -->
    <div v-else class="channels-grid">
      <div
        v-for="(ch, index) in sortedChannels"
        :key="ch.id"
        class="channel-card"
        :class="{ 'channel-live': subStatus(ch) === 'live', 'channel-paper': subStatus(ch) === 'paper', 'dragging': dragIndex === index }"
        draggable="true"
        @dragstart="onDragStart($event, index)"
        @drop="onDrop(index)"
        @dragover.prevent
        @dragenter.prevent
      >
        <div class="channel-card-header">
          <div class="channel-name-row">
            <span class="drag-handle pi pi-bars" title="Drag to reorder"></span>
            <span class="channel-hash">#</span>
            <span class="channel-name">{{ ch.channel_name }}</span>
            <span class="channel-status-badge" :class="'status-' + subStatus(ch)">
              {{ subStatusLabel(ch) }}
            </span>
          </div>
          <div class="channel-meta">
            <span v-if="ch.first_seen_at" class="channel-seen">
              First seen {{ formatDate(ch.first_seen_at) }}
            </span>
            <span v-if="ch.last_message_at" class="channel-seen" :class="{ 'stale-warning-text': isStale(ch) && subStatus(ch) === 'live' }">
              • Last msg: {{ timeSince(ch.last_message_at) }}
              • Last ping: {{ timeSince(channelHeartbeats[ch.channel_name] || ch.last_heartbeat_at) }}
              <i v-if="isStale(ch) && subStatus(ch) === 'live'" class="pi pi-exclamation-triangle" title="No heartbeat in over 1 min" style="font-size: 0.75rem; margin-left: 0.2rem"></i>
            </span>
            <span v-else class="channel-seen" :class="{ 'stale-warning-text': isStale(ch) && subStatus(ch) === 'live' }">
              • No msgs yet
              • Last ping: {{ timeSince(channelHeartbeats[ch.channel_name] || ch.last_heartbeat_at) }}
              <i v-if="isStale(ch) && subStatus(ch) === 'live'" class="pi pi-exclamation-triangle" title="No heartbeat in over 1 min" style="font-size: 0.75rem; margin-left: 0.2rem"></i>
            </span>
            <span v-if="ch.description" class="channel-desc">{{ ch.description }}</span>
          </div>
        </div>

        <!-- Status Control -->
        <div class="channel-controls">
          <label class="control-label">Subscription</label>
          <div class="segmented-control">
            <button
              class="seg-btn"
              :class="{ active: subStatus(ch) === 'off' || subStatus(ch) === 'none' }"
              @click="setSubscription(ch, 'off')"
            >
              ⚫ Off
            </button>
            <button
              class="seg-btn seg-paper"
              :class="{ active: subStatus(ch) === 'paper' }"
              @click="setSubscription(ch, 'paper')"
            >
              🟡 Paper
            </button>
            <button
              class="seg-btn seg-live"
              :class="{ active: subStatus(ch) === 'live' }"
              @click="setSubscription(ch, 'live')"
            >
              🟢 Live
            </button>
          </div>
        </div>

        <!-- Expandable Settings -->
        <div class="channel-settings" v-if="subStatus(ch) !== 'none' && subStatus(ch) !== 'off'">
          <!-- Target Exchanges -->
          <div class="setting-row setting-row-col">
            <label class="control-label">Target Exchanges</label>
            <div v-if="exchangeAccounts.length === 0" class="no-exchanges-hint">
              <span class="pi pi-info-circle"></span>
              No exchange accounts configured. Add one on the
              <router-link to="/exchanges" class="hint-link">Exchanges</router-link> page.
            </div>
            <div v-else class="exchange-pills">
              <button
                v-for="acc in exchangeAccounts"
                :key="acc.id"
                class="exchange-pill"
                :class="{
                  'pill-active': isExchangeMapped(ch, acc.id),
                  ['pill-' + acc.exchange_type]: true,
                }"
                @click="toggleExchangeMapping(ch, acc.id)"
              >
                <span class="pill-icon">{{ exchangeIcon(acc.exchange_type) }}</span>
                <span class="pill-label">{{ acc.label }}</span>
                <span class="pill-check" v-if="isExchangeMapped(ch, acc.id)">✓</span>
              </button>
            </div>
            <div
              v-if="exchangeAccounts.length > 0 && getExchangeIds(ch).length === 0"
              class="mapping-nudge"
            >
              <span class="pi pi-exclamation-circle"></span>
              Select at least one exchange to receive orders from this channel.
            </div>
          </div>

          <div class="setting-row">
            <label class="control-label">TP Rule</label>
            <select
              class="setting-select"
              :value="ch.subscription?.tp_rule || 'halving'"
              @change="updateSetting(ch, 'tp_rule', ($event.target as HTMLSelectElement).value)"
            >
              <option value="halving">Halving (50% each TP)</option>
              <option value="equal_split">Equal Split</option>
              <option value="manual">Manual</option>
            </select>
          </div>

          <div class="setting-row">
            <label class="control-label">Auto-SL after TP1</label>
            <button
              class="toggle-btn"
              :class="{ 'toggle-on': ch.subscription?.auto_sl_after_tp1 }"
              @click="updateSetting(ch, 'auto_sl_after_tp1', !ch.subscription?.auto_sl_after_tp1)"
            >
              {{ ch.subscription?.auto_sl_after_tp1 ? 'ON' : 'OFF' }}
            </button>
          </div>

          <div class="setting-row">
            <label class="control-label">Position Size</label>
            <div style="display: flex; gap: 0.5rem; flex: 1; align-items: center;">
              <select
                class="setting-select"
                style="flex: 1;"
                :value="ch.subscription?.position_size_type || 'min_qty'"
                @change="updateSetting(ch, 'position_size_type', ($event.target as HTMLSelectElement).value)"
              >
                <option value="min_qty">Exchange Min Qty</option>
                <option value="tp_wise_min_qty">TP-wise Min Qty</option>
                <option value="usd_amount">Specific USD Value</option>
              </select>
              <input
                v-if="ch.subscription?.position_size_type === 'usd_amount'"
                type="number"
                class="setting-input"
                style="width: 100px; flex-shrink: 0;"
                v-model.number="ch.subscription!.position_size_value"
                @change="updateSetting(ch, 'position_size_value', ch.subscription!.position_size_value || 0)"
                placeholder="$"
              />
            </div>
          </div>

          <div class="setting-row">
            <label class="control-label">Notes</label>
            <input
              type="text"
              class="setting-input"
              v-model="ch.subscription!.notes"
              @change="updateSetting(ch, 'notes', ch.subscription!.notes || '')"
              placeholder="Add notes..."
            />
          </div>
        </div>

        <!-- Card Footer -->
        <div class="channel-card-footer">
          <button class="manual-call-btn" @click="openManualCallModal(ch)" title="Manual Call">
            <span class="pi pi-bullhorn"></span> Manual Call
          </button>
          <button v-if="isAdmin" class="delete-btn" @click="deleteChannel(ch.id)" title="Delete channel">
            <span class="pi pi-trash"></span>
          </button>
        </div>
      </div>
    </div>

    <!-- Manual Call Modal -->
    <div v-if="showManualCallModal" class="modal-overlay" @click.self="closeManualCallModal">
      <div class="modal-card">
        <h3>Manual Call for #{{ selectedChannel?.channel_name }}</h3>
        <textarea
          v-model="manualCallText"
          class="manual-call-textarea"
          rows="6"
          placeholder="Enter trade call here... (e.g. LONG BTC/USDT Entry: 65000 TP: 66000)"
        ></textarea>
        <div class="modal-actions">
          <button class="btn btn-secondary" @click="closeManualCallModal">Cancel</button>
          <button class="btn btn-primary" :disabled="!manualCallText.trim() || submittingManualCall" @click="submitManualCall">
            {{ submittingManualCall ? 'Sending...' : 'Send Call' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { apiFetch } from '@/lib/api'
import { useAuth } from '@/composables/useAuth'
import { useSystemWS } from '@/composables/useSystemWS'

interface ChannelSubscription {
  id: number
  status: string
  tp_rule: string
  auto_sl_after_tp1: boolean
  position_size_type: string
  position_size_value: number
  notes: string | null
}

interface Channel {
  id: number
  channel_name: string
  description: string | null
  first_seen_at: string | null
  last_message_at?: string | null
  last_heartbeat_at?: string | null
  subscription: ChannelSubscription | null
  exchange_account_ids: number[]
}

interface ExchangeAccountResponse {
  id: number
  exchange_type: string
  label: string
  api_key_masked: string
  is_active: boolean
  is_connected: boolean
  last_error: string
  created_at: string
}

const channels = ref<Channel[]>([])
const exchangeAccounts = ref<ExchangeAccountResponse[]>([])
const loading = ref(true)

const channelsOrder = ref<number[]>([])

const sortedChannels = computed(() => {
  if (!channelsOrder.value.length) return channels.value
  
  const orderMap = new Map(channelsOrder.value.map((id, index) => [id, index]))
  
  return [...channels.value].sort((a, b) => {
    const idxA = orderMap.has(a.id) ? orderMap.get(a.id)! : Infinity
    const idxB = orderMap.has(b.id) ? orderMap.get(b.id)! : Infinity
    return idxA - idxB
  })
})

const dragIndex = ref<number | null>(null)

function onDragStart(event: DragEvent, index: number) {
  dragIndex.value = index
  if (event.dataTransfer) {
    event.dataTransfer.effectAllowed = 'move'
    event.dataTransfer.setData('text/plain', index.toString())
  }
}

function onDrop(dropIndex: number) {
  if (dragIndex.value !== null && dragIndex.value !== dropIndex) {
    const newOrder = sortedChannels.value.map(ch => ch.id)
    const [draggedId] = newOrder.splice(dragIndex.value, 1)
    newOrder.splice(dropIndex, 0, draggedId)
    
    channelsOrder.value = newOrder
    localStorage.setItem('channels_order', JSON.stringify(newOrder))
  }
  dragIndex.value = null
}

// --- Manual Call Setup ---
const showManualCallModal = ref(false)
const selectedChannel = ref<Channel | null>(null)
const manualCallText = ref('')
const submittingManualCall = ref(false)

function openManualCallModal(ch: Channel) {
  selectedChannel.value = ch
  manualCallText.value = ''
  showManualCallModal.value = true
}

function closeManualCallModal() {
  showManualCallModal.value = false
  selectedChannel.value = null
  manualCallText.value = ''
}

async function submitManualCall() {
  if (!selectedChannel.value || !manualCallText.value.trim()) return
  submittingManualCall.value = true
  
  try {
    const payload = {
      channel_name: selectedChannel.value.channel_name,
      text: manualCallText.value
    }

    const res = await apiFetch('/api/messages/manual', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })
    
    if (res.ok) {
      closeManualCallModal()
    } else {
      const err = await res.json()
      alert('Failed to submit manual call: ' + (err.error || err.message || 'Unknown error'))
    }
  } catch(e) {
    console.error('Manual call error:', e)
    alert('Failed to submit manual call.')
  } finally {
    submittingManualCall.value = false
  }
}


const { user } = useAuth()
const isAdmin = computed(() => (user.value?.app_metadata as any)?.role === 'admin')
const { channelHeartbeats } = useSystemWS()

const now = ref(Date.now())
let refreshTimer: ReturnType<typeof setInterval> | null = null

onMounted(async () => {
  const savedOrder = localStorage.getItem('channels_order')
  if (savedOrder) {
    try {
      channelsOrder.value = JSON.parse(savedOrder)
    } catch (e) {
      console.error('Failed to parse saved channel order', e)
    }
  }

  await Promise.all([fetchChannels(), fetchExchangeAccounts()])


  // Update local interval for relative time calculations every second
  refreshTimer = setInterval(() => {
    now.value = Date.now()
  }, 1000)
})

onUnmounted(() => {
  if (refreshTimer) clearInterval(refreshTimer)
})

async function fetchChannels(showLoading = true) {
  if (showLoading) loading.value = true
  try {
    const res = await apiFetch('/api/channels')
    if (res.ok) {
      channels.value = await res.json()
    }
  } catch (err) {
    console.error('Failed to fetch channels:', err)
  } finally {
    loading.value = false
  }
}

async function fetchExchangeAccounts() {
  try {
    const res = await apiFetch('/api/exchange-accounts')
    if (res.ok) {
      exchangeAccounts.value = await res.json()
    }
  } catch (err) {
    console.error('Failed to fetch exchange accounts:', err)
  }
}

function subStatus(ch: Channel): string {
  if (!ch.subscription) return 'none'
  return ch.subscription.status
}

function subStatusLabel(ch: Channel): string {
  const s = subStatus(ch)
  if (s === 'live') return 'Live'
  if (s === 'paper') return 'Paper'
  if (s === 'off') return 'Off'
  return 'Unsubscribed'
}

function formatDate(dateStr: string) {
  const d = new Date(dateStr)
  return `${d.getMonth()+1}/${d.getDate()}/${d.getFullYear()}`
}

function timeSince(dateStr: string | null | undefined): string {
  if (!dateStr) return 'never'
  const diff = Math.max(0, now.value - new Date(dateStr).getTime())
  
  if (diff < 60000) {
    return 'less than a minute ago'
  }
  if (diff < 3600000) {
    const mins = Math.floor(diff / 60000)
    return `${mins}m ago`
  }
  if (diff < 86400000) {
    const hrs = Math.floor(diff / 3600000)
    return `${hrs}h ago`
  }
  const days = Math.floor(diff / 86400000)
  return `${days}d ago`
}

function isStale(ch: Channel): boolean {
  const hb = channelHeartbeats.value[ch.channel_name] || ch.last_heartbeat_at
  if (!hb) return false
  const diffMs = now.value - new Date(hb).getTime()
  return diffMs > 60 * 1000 // 1 minute
}

function exchangeIcon(type: string): string {
  const icons: Record<string, string> = { bitunix: '⚡', phemex: '🔷' }
  return icons[type] || '🔗'
}

function getExchangeIds(ch: Channel): number[] {
  return ch.exchange_account_ids || []
}

function isExchangeMapped(ch: Channel, accountId: number): boolean {
  return getExchangeIds(ch).includes(accountId)
}

function toggleExchangeMapping(ch: Channel, accountId: number) {
  const current = [...getExchangeIds(ch)]
  const idx = current.indexOf(accountId)
  if (idx >= 0) {
    current.splice(idx, 1)
  } else {
    current.push(accountId)
  }
  // Optimistic update
  ch.exchange_account_ids = current
  // Persist
  sendSubscription(ch, {
    exchange_account_ids: current,
  })
}

async function deleteChannel(id: number) {
  if (!confirm('Delete this channel and all its subscriptions?')) return
  try {
    const res = await apiFetch(`/api/channels/${id}`, { method: 'DELETE' })
    if (res.ok) {
      await fetchChannels()
    }
  } catch (err) {
    console.error('Delete channel error:', err)
  }
}

async function setSubscription(ch: Channel, status: string) {
  const sub = ch.subscription
  await sendSubscription(ch, {
    status,
    tp_rule: sub?.tp_rule || 'halving',
    auto_sl_after_tp1: sub?.auto_sl_after_tp1 || false,
    position_size_type: sub?.position_size_type || 'min_qty',
    position_size_value: sub?.position_size_value || 0,
    notes: sub?.notes || '',
    exchange_account_ids: status === 'off' ? [] : getExchangeIds(ch),
  })
}

async function updateSetting(ch: Channel, field: string, value: any) {
  const sub = ch.subscription
  if (!sub) return

  const body: any = {
    status: sub.status,
    tp_rule: sub.tp_rule,
    auto_sl_after_tp1: sub.auto_sl_after_tp1,
    position_size_type: sub.position_size_type,
    position_size_value: sub.position_size_value,
    notes: sub.notes || '',
    exchange_account_ids: getExchangeIds(ch),
  }
  body[field] = value

  await sendSubscription(ch, body)
}

async function sendSubscription(ch: Channel, overrides: Record<string, any>) {
  const sub = ch.subscription
  const body: any = {
    status: sub?.status || 'off',
    tp_rule: sub?.tp_rule || 'halving',
    auto_sl_after_tp1: sub?.auto_sl_after_tp1 || false,
    position_size_type: sub?.position_size_type || 'min_qty',
    position_size_value: sub?.position_size_value || 0,
    notes: sub?.notes || '',
    exchange_account_ids: getExchangeIds(ch),
    ...overrides,
  }

  try {
    const res = await apiFetch(`/api/channels/${ch.id}/subscribe`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    })
    if (res.ok) {
      await fetchChannels()
    }
  } catch (err) {
    console.error('Subscription update error:', err)
  }
}
</script>

<style scoped>
.feed-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 1.5rem;
}

.pos-summary {
  display: flex;
  gap: 1rem;
  margin-bottom: 1.5rem;
}

.pos-summary-card {
  flex: 1;
  background: var(--surface-card);
  border: 1px solid var(--surface-border);
  border-radius: 12px;
  padding: 1.25rem;
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}

.pos-summary-label {
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-color-secondary);
}

.pos-summary-value {
  font-size: 1.35rem;
  font-weight: 700;
}

/* Channels Grid */
.channels-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(380px, 1fr));
  gap: 1rem;
}

.channel-card {
  background: var(--surface-card);
  border: 1px solid var(--surface-border);
  border-radius: 14px;
  padding: 1.25rem;
  transition: all 0.2s;
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.channel-card:hover {
  border-color: rgba(99, 102, 241, 0.3);
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.2);
}

.channel-card.channel-live {
  border-left: 3px solid var(--green-badge);
}

.channel-card.channel-paper {
  border-left: 3px solid var(--amber-badge);
}

.channel-card.dragging {
  opacity: 0.5;
  box-shadow: 0 0 0 2px var(--primary-color) inset;
}

.channel-card-header {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.channel-name-row {
  display: flex;
  align-items: center;
  gap: 0.35rem;
}

.drag-handle {
  cursor: grab;
  color: var(--text-color-secondary);
  opacity: 0.5;
  margin-right: 0.2rem;
  font-size: 1.1rem;
}

.drag-handle:hover {
  opacity: 1;
  color: var(--text-color);
}

.channel-hash {
  font-size: 1.15rem;
  font-weight: 700;
  color: var(--text-color-secondary);
  opacity: 0.5;
}

.channel-name {
  font-size: 1.05rem;
  font-weight: 700;
  color: var(--text-color);
  flex: 1;
}

.channel-status-badge {
  display: inline-flex;
  align-items: center;
  padding: 0.2rem 0.6rem;
  border-radius: 100px;
  font-size: 0.7rem;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.status-live {
  background: rgba(34, 197, 94, 0.12);
  border: 1px solid rgba(34, 197, 94, 0.3);
  color: var(--green-badge);
}

.status-paper {
  background: rgba(245, 158, 11, 0.12);
  border: 1px solid rgba(245, 158, 11, 0.3);
  color: var(--amber-badge);
}

.status-off {
  background: rgba(148, 163, 184, 0.1);
  border: 1px solid rgba(148, 163, 184, 0.2);
  color: var(--text-color-secondary);
}

.status-none {
  background: rgba(148, 163, 184, 0.06);
  border: 1px solid rgba(148, 163, 184, 0.15);
  color: var(--text-color-secondary);
  opacity: 0.6;
}

.channel-meta {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  font-size: 0.78rem;
  color: var(--text-color-secondary);
}

.stale-warning-text {
  color: var(--amber-badge);
  font-weight: 600;
}

/* Control Area */
.channel-controls {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.control-label {
  font-size: 0.72rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-color-secondary);
}

.segmented-control {
  display: flex;
  background: rgba(15, 23, 42, 0.6);
  border-radius: 10px;
  border: 1px solid var(--surface-border);
  overflow: hidden;
}

.seg-btn {
  flex: 1;
  padding: 0.55rem 0.75rem;
  border: none;
  background: transparent;
  color: var(--text-color-secondary);
  font-size: 0.8rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
}

.seg-btn:not(:last-child) {
  border-right: 1px solid var(--surface-border);
}

.seg-btn:hover {
  background: rgba(99, 102, 241, 0.08);
}

.seg-btn.active {
  background: rgba(148, 163, 184, 0.15);
  color: var(--text-color);
}

.seg-btn.seg-paper.active {
  background: rgba(245, 158, 11, 0.15);
  color: var(--amber-badge);
}

.seg-btn.seg-live.active {
  background: rgba(34, 197, 94, 0.15);
  color: var(--green-badge);
}

/* Settings */
.channel-settings {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  padding-top: 0.5rem;
  border-top: 1px solid var(--surface-border);
  animation: fadeIn 0.2s ease;
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(-4px); }
  to { opacity: 1; transform: translateY(0); }
}

.setting-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
}

.setting-row-col {
  flex-direction: column;
  align-items: stretch;
}

.setting-select {
  background: var(--surface-ground);
  border: 1px solid var(--surface-border);
  border-radius: 8px;
  color: var(--text-color);
  padding: 0.45rem 0.75rem;
  font-size: 0.82rem;
  min-width: 180px;
  cursor: pointer;
}

.setting-select:focus {
  outline: none;
  border-color: var(--primary-color);
}

.setting-input {
  background: var(--surface-ground);
  border: 1px solid var(--surface-border);
  border-radius: 8px;
  color: var(--text-color);
  padding: 0.45rem 0.75rem;
  font-size: 0.82rem;
  flex: 1;
  min-width: 0;
}

.setting-input:focus {
  outline: none;
  border-color: var(--primary-color);
}

.setting-input::placeholder {
  color: var(--text-color-secondary);
  opacity: 0.5;
}

.toggle-btn {
  padding: 0.35rem 0.85rem;
  border-radius: 8px;
  border: 1px solid var(--surface-border);
  background: var(--surface-ground);
  color: var(--text-color-secondary);
  font-size: 0.78rem;
  font-weight: 700;
  cursor: pointer;
  transition: all 0.2s;
  min-width: 60px;
}

.toggle-btn.toggle-on {
  background: rgba(34, 197, 94, 0.15);
  border-color: rgba(34, 197, 94, 0.3);
  color: var(--green-badge);
}

/* Exchange Pills */
.exchange-pills {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.exchange-pill {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.45rem 0.85rem;
  border-radius: 100px;
  border: 1.5px solid var(--surface-border);
  background: var(--surface-ground);
  color: var(--text-color-secondary);
  font-size: 0.8rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
  user-select: none;
}

.exchange-pill:hover {
  border-color: rgba(99, 102, 241, 0.4);
  background: rgba(99, 102, 241, 0.06);
}

.exchange-pill.pill-active {
  color: var(--text-color);
  box-shadow: 0 0 0 1px currentColor;
}

.exchange-pill.pill-active.pill-bitunix {
  border-color: rgba(34, 197, 94, 0.5);
  background: rgba(34, 197, 94, 0.1);
  color: var(--green-badge);
  box-shadow: 0 0 0 1px rgba(34, 197, 94, 0.3);
}

.exchange-pill.pill-active.pill-phemex {
  border-color: rgba(99, 102, 241, 0.5);
  background: rgba(99, 102, 241, 0.1);
  color: #818cf8;
  box-shadow: 0 0 0 1px rgba(99, 102, 241, 0.3);
}

.pill-icon {
  font-size: 0.9rem;
}

.pill-label {
  max-width: 140px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pill-check {
  font-size: 0.75rem;
  font-weight: 800;
}

.no-exchanges-hint {
  display: flex;
  align-items: center;
  gap: 0.45rem;
  font-size: 0.8rem;
  color: var(--text-color-secondary);
  opacity: 0.75;
  padding: 0.35rem 0;
}

.no-exchanges-hint .pi {
  font-size: 0.85rem;
}

.hint-link {
  color: var(--primary-color);
  text-decoration: none;
  font-weight: 600;
}

.hint-link:hover {
  text-decoration: underline;
}

.mapping-nudge {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  margin-top: 0.25rem;
  font-size: 0.75rem;
  color: var(--amber-badge);
  opacity: 0.85;
}

.mapping-nudge .pi {
  font-size: 0.8rem;
}

/* Card Footer */
.channel-card-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding-top: 0.5rem;
  border-top: 1px solid var(--surface-border);
}

.delete-btn {
  background: none;
  border: none;
  color: var(--text-color-secondary);
  cursor: pointer;
  padding: 0.35rem;
  border-radius: 6px;
  transition: all 0.15s ease;
  opacity: 0.5;
}

.delete-btn:hover {
  color: var(--red-badge);
  background: rgba(239, 68, 68, 0.1);
  opacity: 1;
}



@media (max-width: 768px) {
  .channels-grid {
    grid-template-columns: 1fr;
  }

  .pos-summary {
    flex-wrap: wrap;
  }

  .pos-summary-card {
    min-width: calc(50% - 0.5rem);
  }
}

/* Modal */
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  background: rgba(0, 0, 0, 0.6);
  backdrop-filter: blur(4px);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}

.modal-card {
  background: var(--surface-card);
  border: 1px solid var(--surface-border);
  border-radius: 12px;
  width: 90%;
  max-width: 500px;
  padding: 1.5rem;
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.5);
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.modal-card h3 {
  margin: 0;
  font-size: 1.2rem;
  color: var(--text-color);
}

.manual-call-textarea {
  background: var(--surface-ground);
  border: 1px solid var(--surface-border);
  border-radius: 8px;
  color: var(--text-color);
  padding: 0.75rem;
  font-family: inherit;
  font-size: 0.9rem;
  resize: vertical;
}

.manual-call-textarea:focus {
  outline: none;
  border-color: var(--primary-color);
}

.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.75rem;
  margin-top: 0.5rem;
}

.btn {
  padding: 0.55rem 1rem;
  border-radius: 8px;
  font-weight: 600;
  cursor: pointer;
  border: none;
  transition: all 0.2s;
}

.btn-secondary {
  background: transparent;
  color: var(--text-color-secondary);
}

.btn-secondary:hover {
  background: rgba(255, 255, 255, 0.05);
  color: var(--text-color);
}

.btn-primary {
  background: var(--primary-color);
  color: white;
}

.btn-primary:hover:not(:disabled) {
  filter: brightness(1.1);
}

.btn-primary:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.manual-call-btn {
  background: rgba(99, 102, 241, 0.1);
  border: 1px solid rgba(99, 102, 241, 0.3);
  color: #818cf8;
  cursor: pointer;
  padding: 0.35rem 0.75rem;
  border-radius: 6px;
  font-size: 0.8rem;
  font-weight: 600;
  transition: all 0.15s ease;
  display: flex;
  align-items: center;
  gap: 0.4rem;
}

.manual-call-btn:hover {
  background: rgba(99, 102, 241, 0.2);
  border-color: rgba(99, 102, 241, 0.5);
}
</style>
