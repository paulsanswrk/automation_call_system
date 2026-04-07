<template>
  <div>
    <div class="feed-header">
      <div class="live-badge" :class="connectionClass">
        <span class="live-dot" :style="{ background: connectionColor }"></span>
        {{ connectionLabel }}
      </div>
    </div>

    <div v-if="loading" class="empty-state">
      <div class="spinner" style="margin: 0 auto;"></div>
    </div>

    <div v-else-if="positions.length === 0" class="empty-state">
      <div class="empty-icon">📊</div>
      <h2>No open positions</h2>
      <p>Open futures positions on connected exchanges will appear here in real-time.</p>
    </div>

    <div v-else>
      <div class="pos-summary">
        <div class="pos-summary-card">
          <span class="pos-summary-label">Unrealized PnL</span>
          <span class="pos-summary-value" :class="totalPnlClass">{{ totalPnl }}</span>
        </div>
      </div>

      <div v-for="group in groupedPositions" :key="group.exchange" class="pos-exchange-group">
        <div class="pos-exchange-header">
          <span class="pos-exchange-badge" :class="'badge-' + group.exchange.toLowerCase()">{{ group.exchange }}</span>
          <span class="pos-exchange-count">{{ group.positions.length }} position{{ group.positions.length > 1 ? 's' : '' }}</span>
        </div>

        <div class="pos-table-wrap">
          <table class="pos-table">
            <thead>
              <tr>
                <th>Symbol</th>
                <th>Side</th>
                <th>Qty</th>
                <th>Entry</th>
                <th>Mark</th>
                <th>PnL</th>
                <th>Lev</th>
                <th>Liq. Price</th>
                <th>Margin</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="pos in group.positions" :key="pos.positionId" class="pos-row">
                <td class="pos-symbol">{{ pos.symbol }}</td>
                <td>
                  <span class="pos-side-badge" :class="pos.side === 'LONG' ? 'pos-long' : 'pos-short'">
                    {{ pos.side }}
                  </span>
                </td>
                <td class="pos-mono">{{ pos.qty }}</td>
                <td class="pos-mono">{{ formatPrice(pos.entryPrice) }}</td>
                <td class="pos-mono">{{ formatPrice(pos.markPrice) }}</td>
                <td class="pos-mono" :class="pnlClass(pos.unrealizedPnl)">
                  {{ formatPnl(pos.unrealizedPnl) }}
                </td>
                <td class="pos-mono">{{ pos.leverage }}x</td>
                <td class="pos-mono">{{ formatPrice(pos.liquidationPrice) }}</td>
                <td>
                  <span class="pos-margin-badge">{{ pos.marginMode }}</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { supabase } from '@/lib/supabase'

interface Position {
  exchange: string
  positionId: string
  symbol: string
  side: string
  qty: string
  entryPrice: string
  markPrice: string
  leverage: string
  unrealizedPnl: string
  realizedPnl: string
  liquidationPrice: string
  marginMode: string
  margin: string
  updatedAt: string
}

const positions = ref<Position[]>([])
const loading = ref(true)
const wsStatus = ref<'connecting' | 'connected' | 'disconnected'>('connecting')
let ws: WebSocket | null = null
let reconnectTimer: number | null = null

const connectionClass = computed(() => ({
  'live-badge': true,
  'live-connected': wsStatus.value === 'connected',
  'live-disconnected': wsStatus.value === 'disconnected',
  'live-connecting': wsStatus.value === 'connecting',
}))

const connectionColor = computed(() => {
  switch (wsStatus.value) {
    case 'connected': return '#22c55e'
    case 'connecting': return '#f59e0b'
    case 'disconnected': return '#ef4444'
  }
})

const connectionLabel = computed(() => {
  switch (wsStatus.value) {
    case 'connected': return 'Live'
    case 'connecting': return 'Connecting…'
    case 'disconnected': return 'Disconnected'
  }
})

const groupedPositions = computed(() => {
  const map: Record<string, Position[]> = {}
  for (const pos of positions.value) {
    if (!map[pos.exchange]) map[pos.exchange] = []
    map[pos.exchange].push(pos)
  }
  return Object.keys(map).sort().map(ex => ({
    exchange: ex,
    positions: map[ex].sort((a, b) => a.symbol !== b.symbol ? a.symbol.localeCompare(b.symbol) : a.side.localeCompare(b.side)),
  }))
})

const totalPnl = computed(() => {
  let total = 0
  for (const pos of positions.value) {
    const val = parseFloat(pos.unrealizedPnl || '0')
    if (!isNaN(val)) total += val
  }
  const sign = total >= 0 ? '+' : ''
  return `${sign}${total.toFixed(2)} USDT`
})

const totalPnlClass = computed(() => {
  let total = 0
  for (const pos of positions.value) {
    const val = parseFloat(pos.unrealizedPnl || '0')
    if (!isNaN(val)) total += val
  }
  return total >= 0 ? 'pnl-positive' : 'pnl-negative'
})

function pnlClass(pnl: string) {
  return parseFloat(pnl || '0') >= 0 ? 'pnl-positive' : 'pnl-negative'
}

function formatPnl(pnl: string) {
  const val = parseFloat(pnl || '0')
  if (isNaN(val)) return pnl || '—'
  return `${val >= 0 ? '+' : ''}${val.toFixed(2)}`
}

function formatPrice(price: string) {
  if (!price || price === '0') return '—'
  const val = parseFloat(price)
  if (isNaN(val)) return price
  if (val >= 100) return val.toFixed(2)
  if (val >= 1) return val.toFixed(4)
  return val.toFixed(6)
}

async function connectWebSocket() {
  wsStatus.value = 'connecting'
  const { data: { session } } = await supabase.auth.getSession()
  if (!session?.access_token) {
    wsStatus.value = 'disconnected'
    return
  }

  const API_BASE = import.meta.env.VITE_API_BASE_URL ?? ''
  const wsBase = API_BASE
    ? API_BASE.replace(/^http/, 'ws')
    : `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}`

  ws = new WebSocket(`${wsBase}/api/positions/ws?token=${encodeURIComponent(session.access_token)}`)

  ws.onopen = () => { wsStatus.value = 'connected'; loading.value = false }

  ws.onmessage = (event) => {
    try {
      const msg = JSON.parse(event.data)
      if (msg.type === 'snapshot') {
        positions.value = msg.positions || []
      } else if (msg.type === 'update') {
        const others = positions.value.filter(p => p.exchange !== msg.exchange)
        positions.value = [...others, ...(msg.positions || [])]
      } else if (msg.type === 'remove') {
        const toRemove = new Set((msg.positions || []).map((p: Position) => p.positionId))
        positions.value = positions.value.filter(p => !toRemove.has(p.positionId))
      }
    } catch (err) {
      console.error('[positions] WS parse error:', err)
    }
  }

  ws.onclose = () => {
    wsStatus.value = 'disconnected'
    reconnectTimer = window.setTimeout(connectWebSocket, 3000)
  }

  ws.onerror = (err) => console.error('[positions] WS error:', err)
}

async function fetchInitialData() {
  loading.value = true
  try {
    const { data: { session } } = await supabase.auth.getSession()
    const API_BASE = import.meta.env.VITE_API_BASE_URL ?? ''
    const res = await fetch(`${API_BASE}/api/positions`, {
      headers: { Authorization: `Bearer ${session?.access_token ?? ''}` },
    })
    if (res.ok) positions.value = await res.json()
  } catch (err) {
    console.error('[positions] REST fetch error:', err)
  } finally {
    loading.value = false
  }
}

onMounted(async () => {
  await fetchInitialData()
  connectWebSocket()
})

onUnmounted(() => {
  if (reconnectTimer) clearTimeout(reconnectTimer)
  if (ws) { ws.onclose = null; ws.close() }
})
</script>

<style scoped>
.pos-exchange-group { margin-bottom: 1.5rem; }
.pos-exchange-header { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.75rem; }
.pos-exchange-count { font-size: 0.8rem; color: var(--text-color-secondary); }
</style>
