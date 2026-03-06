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
      <!-- Summary cards -->
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

        <!-- Mobile cards -->
        <div class="pos-cards-mobile">
          <div v-for="pos in group.positions" :key="'m-'+pos.positionId" class="pos-card-mobile">
            <div class="pos-card-top">
              <span class="pos-symbol">{{ pos.symbol }}</span>
              <span class="pos-side-badge" :class="pos.side === 'LONG' ? 'pos-long' : 'pos-short'">
                {{ pos.side }}
              </span>
              <span class="pos-margin-badge">{{ pos.marginMode }}</span>
            </div>
            <div class="pos-card-grid">
              <div><span class="pos-card-label">Qty</span><span class="pos-mono">{{ pos.qty }}</span></div>
              <div><span class="pos-card-label">Entry</span><span class="pos-mono">{{ formatPrice(pos.entryPrice) }}</span></div>
              <div><span class="pos-card-label">Mark</span><span class="pos-mono">{{ formatPrice(pos.markPrice) }}</span></div>
              <div><span class="pos-card-label">PnL</span><span class="pos-mono" :class="pnlClass(pos.unrealizedPnl)">{{ formatPnl(pos.unrealizedPnl) }}</span></div>
              <div><span class="pos-card-label">Leverage</span><span class="pos-mono">{{ pos.leverage }}x</span></div>
              <div><span class="pos-card-label">Liq.</span><span class="pos-mono">{{ formatPrice(pos.liquidationPrice) }}</span></div>
            </div>
          </div>
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
  return Object.keys(map).sort().map(ex => {
    const sortedPos = map[ex].sort((a, b) => {
      if (a.symbol !== b.symbol) return a.symbol.localeCompare(b.symbol)
      return a.side.localeCompare(b.side)
    })
    return {
      exchange: ex,
      positions: sortedPos
    }
  })
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
  const val = parseFloat(pnl || '0')
  return val >= 0 ? 'pnl-positive' : 'pnl-negative'
}

function formatPnl(pnl: string) {
  const val = parseFloat(pnl || '0')
  if (isNaN(val)) return pnl || '—'
  const sign = val >= 0 ? '+' : ''
  return `${sign}${val.toFixed(2)}`
}

function formatPrice(price: string) {
  if (!price || price === '0') return '—'
  const val = parseFloat(price)
  if (isNaN(val)) return price
  // Auto-detect decimal places
  if (val >= 100) return val.toFixed(2)
  if (val >= 1) return val.toFixed(4)
  return val.toFixed(6)
}

async function connectWebSocket() {
  wsStatus.value = 'connecting'

  // Get JWT for auth
  const { data: { session } } = await supabase.auth.getSession()
  if (!session?.access_token) {
    console.error('[positions] No auth session')
    wsStatus.value = 'disconnected'
    return
  }

  const API_BASE = import.meta.env.VITE_API_BASE_URL ?? ''
  const wsBase = API_BASE
    ? API_BASE.replace(/^http/, 'ws')
    : `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}`

  const wsUrl = `${wsBase}/api/positions/ws?token=${encodeURIComponent(session.access_token)}`

  ws = new WebSocket(wsUrl)

  ws.onopen = () => {
    wsStatus.value = 'connected'
    loading.value = false
  }

  ws.onmessage = (event) => {
    try {
      const msg = JSON.parse(event.data)
      if (msg.type === 'snapshot') {
        positions.value = msg.positions || []
      } else if (msg.type === 'update') {
        // Merge updated positions from this exchange
        const exchangeName = msg.exchange
        const others = positions.value.filter(p => p.exchange !== exchangeName)
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
    // Reconnect after 3s
    reconnectTimer = window.setTimeout(connectWebSocket, 3000)
  }

  ws.onerror = (err) => {
    console.error('[positions] WS error:', err)
  }
}

async function fetchInitialData() {
  loading.value = true
  try {
    const { data: { session } } = await supabase.auth.getSession()
    const API_BASE = import.meta.env.VITE_API_BASE_URL ?? ''
    const res = await fetch(`${API_BASE}/api/positions`, {
      headers: { Authorization: `Bearer ${session?.access_token ?? ''}` },
    })
    if (res.ok) {
      positions.value = await res.json()
    }
  } catch (err) {
    console.error('[positions] REST fetch error:', err)
  } finally {
    loading.value = false
  }
}

onMounted(async () => {
  // Fetch initial via REST, then connect WS
  await fetchInitialData()
  connectWebSocket()
})

onUnmounted(() => {
  if (reconnectTimer) clearTimeout(reconnectTimer)
  if (ws) {
    ws.onclose = null // prevent reconnect
    ws.close()
  }
})
</script>

<style scoped>
/* Summary cards */
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

/* Exchange group */
.pos-exchange-group {
  margin-bottom: 1.5rem;
}

.pos-exchange-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  margin-bottom: 0.75rem;
}

.pos-exchange-badge {
  color: white;
  padding: 0.3rem 0.8rem;
  border-radius: 6px;
  font-size: 0.8rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.badge-bitunix {
  background: linear-gradient(135deg, #3b82f6, #60a5fa); /* Blue */
}

.badge-phemex {
  background: linear-gradient(135deg, #10b981, #34d399); /* Emerald Green */
}

.pos-exchange-count {
  font-size: 0.8rem;
  color: var(--text-color-secondary);
}

/* Table */
.pos-table-wrap {
  overflow-x: auto;
  border-radius: 12px;
  border: 1px solid var(--surface-border);
}

.pos-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.85rem;
}

.pos-table thead th {
  background: rgba(99, 102, 241, 0.08);
  padding: 0.75rem 0.85rem;
  text-align: left;
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-color-secondary);
  white-space: nowrap;
}

.pos-table tbody td {
  padding: 0.85rem;
  border-top: 1px solid var(--surface-border);
  background: var(--surface-card);
}

.pos-row:hover td {
  background: rgba(99, 102, 241, 0.05);
}

.pos-symbol {
  font-weight: 600;
  color: var(--text-color);
}

.pos-mono {
  font-family: 'JetBrains Mono', 'Fira Code', monospace;
  font-size: 0.82rem;
}

.pos-side-badge {
  display: inline-block;
  padding: 0.2rem 0.55rem;
  border-radius: 4px;
  font-size: 0.72rem;
  font-weight: 700;
  letter-spacing: 0.03em;
}

.pos-long {
  background: rgba(34, 197, 94, 0.12);
  border: 1px solid rgba(34, 197, 94, 0.3);
  color: #22c55e;
}

.pos-short {
  background: rgba(239, 68, 68, 0.12);
  border: 1px solid rgba(239, 68, 68, 0.3);
  color: #ef4444;
}

.pos-margin-badge {
  display: inline-block;
  padding: 0.15rem 0.45rem;
  border-radius: 4px;
  font-size: 0.68rem;
  font-weight: 600;
  background: rgba(148, 163, 184, 0.12);
  border: 1px solid rgba(148, 163, 184, 0.2);
  color: var(--text-color-secondary);
}

.pnl-positive {
  color: #22c55e;
}

.pnl-negative {
  color: #ef4444;
}

/* Connection badge variants */
.live-connected {
  border-color: rgba(34, 197, 94, 0.3) !important;
  color: #22c55e !important;
  background: rgba(34, 197, 94, 0.1) !important;
}

.live-connecting {
  border-color: rgba(245, 158, 11, 0.3) !important;
  color: #f59e0b !important;
  background: rgba(245, 158, 11, 0.1) !important;
}

.live-disconnected {
  border-color: rgba(239, 68, 68, 0.3) !important;
  color: #ef4444 !important;
  background: rgba(239, 68, 68, 0.1) !important;
}

/* Mobile cards (hidden on desktop) */
.pos-cards-mobile {
  display: none;
}

@media (max-width: 768px) {
  .pos-summary {
    flex-direction: column;
  }

  .pos-table-wrap {
    display: none;
  }

  .pos-cards-mobile {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .pos-card-mobile {
    background: var(--surface-card);
    border: 1px solid var(--surface-border);
    border-radius: 12px;
    padding: 1rem;
  }

  .pos-card-top {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 0.75rem;
    padding-bottom: 0.75rem;
    border-bottom: 1px solid var(--surface-border);
  }

  .pos-card-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.65rem;
  }

  .pos-card-label {
    display: block;
    font-size: 0.7rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--text-color-secondary);
    margin-bottom: 0.15rem;
  }
}
</style>
