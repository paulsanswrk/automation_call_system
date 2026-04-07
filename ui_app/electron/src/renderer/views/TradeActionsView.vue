<template>
  <div>
    <!-- Filter Bar -->
    <div class="filter-row">
      <select v-model="filterAction" class="setting-input filter-input" @change="applyFilter">
        <option value="">All Actions</option>
        <option value="PLACE_ORDER">PLACE_ORDER</option>
        <option value="SKIP">SKIP</option>
        <option value="ERROR">ERROR</option>
        <option value="AUTO_SL_BREAKEVEN">AUTO_SL_BREAKEVEN</option>
      </select>
      <input type="date" v-model="filterDateFrom" class="setting-input filter-input" @change="applyFilter" />
      <input type="date" v-model="filterDateTo" class="setting-input filter-input" @change="applyFilter" />
      <button @click="applyFilter" class="btn" :disabled="loading">Filter</button>
      <div style="flex: 1"></div>
      <button @click="bulkDelete" class="btn btn-danger" :disabled="loading || (!filterAction && !filterDateFrom)" v-if="isAdmin">
        🗑 Delete All
      </button>
    </div>

    <div v-if="loading && actions.length === 0" class="empty-state">
      <div class="spinner" style="margin: 0 auto;"></div>
    </div>

    <div v-else-if="actions.length === 0" class="empty-state">
      <div class="empty-icon">📋</div>
      <h2>No Trade Actions</h2>
      <p>Trade actions will appear here when the AI evaluates a call.</p>
    </div>

    <div v-else>
      <div class="pos-table-wrap" style="margin-bottom: 1rem;">
        <table class="pos-table">
          <thead>
            <tr>
              <th>Time</th>
              <th>Action</th>
              <th>Exchange</th>
              <th>Symbol</th>
              <th>Side</th>
              <th>Price</th>
              <th>Qty</th>
              <th>Order ID</th>
              <th>Notes</th>
              <th v-if="isAdmin">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="action in actions" :key="action.id" class="pos-row" @click="selectedAction = action">
              <td style="white-space: nowrap">{{ formatTimeChunk(action.created_at) }}</td>
              <td>
                <span class="action-badge" :class="{
                  'place-order': action.action === 'PLACE_ORDER',
                  'skip': action.action === 'SKIP',
                  'error': action.action === 'ERROR',
                  'auto-sl': action.action === 'AUTO_SL_BREAKEVEN'
                }">{{ action.action }}</span>
              </td>
              <td><span class="pos-margin-badge" v-if="action.exchange">{{ action.exchange }}</span></td>
              <td class="pos-symbol">{{ action.symbol || '—' }}</td>
              <td>
                <span class="pos-side-badge" :class="action.side === 'LONG' || action.side === 'BUY' ? 'pos-long' : 'pos-short'" v-if="action.side">{{ action.side }}</span>
                <span v-else>—</span>
              </td>
              <td class="pos-mono">{{ action.price || '—' }}</td>
              <td class="pos-mono">{{ action.qty || '—' }}</td>
              <td class="pos-mono trunc-cell" style="max-width: 100px">{{ action.order_id || '—' }}</td>
              <td class="trunc-cell" style="max-width: 150px">{{ action.notes || '—' }}</td>
              <td v-if="isAdmin" @click.stop>
                <button class="delete-btn" @click="deleteAction(action.id)" title="Delete">🗑</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="pagination-controls">
        <button class="btn" :disabled="currentPage === 1" @click="changePage(currentPage - 1)">Previous</button>
        <span class="page-info">Page {{ currentPage }} of {{ totalPages || 1 }}</span>
        <button class="btn" :disabled="currentPage >= totalPages" @click="changePage(currentPage + 1)">Next</button>
      </div>
    </div>

    <!-- Detail Modal -->
    <div v-if="selectedAction" class="detail-overlay" @click.self="selectedAction = null">
      <div class="detail-panel" style="max-width: 700px;">
        <button class="detail-close" @click="selectedAction = null">✕</button>
        <div class="detail-section">
          <h3>Trade Action Details</h3>
          <table class="detail-table">
            <tr><td>Time</td><td>{{ new Date(selectedAction.created_at).toLocaleString() }}</td></tr>
            <tr><td>Action</td><td><span class="action-badge" :class="{ 'place-order': selectedAction.action === 'PLACE_ORDER', 'skip': selectedAction.action === 'SKIP', 'error': selectedAction.action === 'ERROR', 'auto-sl': selectedAction.action === 'AUTO_SL_BREAKEVEN' }">{{ selectedAction.action }}</span></td></tr>
            <tr v-if="selectedAction.exchange"><td>Exchange</td><td>{{ selectedAction.exchange }}</td></tr>
            <tr v-if="selectedAction.symbol"><td>Symbol</td><td>{{ selectedAction.symbol }}</td></tr>
            <tr v-if="selectedAction.side"><td>Side</td><td>{{ selectedAction.side }}</td></tr>
            <tr v-if="selectedAction.order_type"><td>Order Type</td><td>{{ selectedAction.order_type }}</td></tr>
            <tr v-if="selectedAction.price"><td>Price</td><td>{{ selectedAction.price }}</td></tr>
            <tr v-if="selectedAction.qty"><td>Qty</td><td>{{ selectedAction.qty }}</td></tr>
            <tr v-if="selectedAction.order_id"><td>Order ID</td><td class="pos-mono">{{ selectedAction.order_id }}</td></tr>
            <tr v-if="selectedAction.notes"><td>Notes</td><td>{{ selectedAction.notes }}</td></tr>
          </table>
        </div>
        <div class="detail-section" v-if="selectedAction.request">
          <h3>API Request</h3>
          <pre class="code-block">{{ formatJSON(selectedAction.request) }}</pre>
        </div>
        <div class="detail-section" v-if="selectedAction.result">
          <h3>API Result</h3>
          <pre class="code-block">{{ formatJSON(selectedAction.result) }}</pre>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, computed, watch } from 'vue'
import { apiFetch } from '@/lib/api'
import { useAuth } from '@/composables/useAuth'
import { useSystemWS } from '@/composables/useSystemWS'

interface TradeAction {
  id: number; created_at: string; discord_message_id: string; action: string; exchange: string; symbol: string; side: string; order_type: string; qty: string; price: string; order_id: string; sl_price: string; notes: string; request: any; result: any; client_id: string
}

const actions = ref<TradeAction[]>([])
const loading = ref(true)
const totalCount = ref(0)
const currentPage = ref(1)
const limit = ref(25)
const selectedAction = ref<TradeAction | null>(null)

const filterAction = ref('')
const filterDateFrom = ref('')
const filterDateTo = ref('')

const { user } = useAuth()
const isAdmin = computed(() => (user.value?.app_metadata as any)?.role === 'admin')
const totalPages = computed(() => Math.ceil(totalCount.value / limit.value))
const { latestTradeAction } = useSystemWS()

onMounted(async () => { await fetchData() })

watch(latestTradeAction, (newAction) => {
  if (newAction && currentPage.value === 1) {
    if (!filterAction.value || newAction.action === filterAction.value) { actions.value.unshift(newAction); totalCount.value++; if (actions.value.length > limit.value) actions.value.pop() }
  }
})

async function fetchData(page = 1) {
  loading.value = true
  try {
    let url = `/api/trade-actions?page=${page}&limit=${limit.value}`
    if (filterAction.value) url += `&action=${encodeURIComponent(filterAction.value)}`
    if (filterDateFrom.value) url += `&date_from=${filterDateFrom.value}`
    if (filterDateTo.value) url += `&date_to=${filterDateTo.value}`
    const res = await apiFetch(url)
    if (res.ok) { const json = await res.json(); actions.value = json.data || []; totalCount.value = json.total || 0; currentPage.value = json.page }
  } catch (err) { console.error('Failed to fetch trade actions:', err) }
  finally { loading.value = false }
}

async function applyFilter() { await fetchData(1) }

async function bulkDelete() {
  if (!filterAction.value && !filterDateFrom.value) { alert('Please apply at least one filter.'); return }
  let msg = 'Delete ALL actions matching filters:\n'
  if (filterAction.value) msg += `- Action: ${filterAction.value}\n`
  if (filterDateFrom.value) msg += `- From: ${filterDateFrom.value}\n`
  if (filterDateTo.value) msg += `- To: ${filterDateTo.value}\n`
  msg += '\nThis cannot be undone.'
  if (!confirm(msg)) return
  loading.value = true
  try {
    let url = '/api/trade-actions?'
    if (filterAction.value) url += `action=${encodeURIComponent(filterAction.value)}&`
    if (filterDateFrom.value) url += `date_from=${filterDateFrom.value}&`
    if (filterDateTo.value) url += `date_to=${filterDateTo.value}`
    const res = await apiFetch(url, { method: 'DELETE' })
    if (res.ok) { const data = await res.json(); alert(`Deleted ${data.count} actions.`); await fetchData(1) }
    else { const err = await res.json(); alert('Delete failed: ' + err.error) }
  } catch { alert('Delete failed.') }
  finally { loading.value = false }
}

async function changePage(page: number) { if (page < 1 || page > totalPages.value) return; await fetchData(page) }
async function deleteAction(id: number) { try { const res = await apiFetch(`/api/trade-actions/${id}`, { method: 'DELETE' }); if (res.ok) await fetchData(currentPage.value) } catch (err) { console.error('Delete error:', err) } }
function formatTimeChunk(dStr: string) { const d = new Date(dStr); return `${d.getMonth()+1}/${d.getDate()} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}` }
function formatJSON(val: any) { if (!val) return ''; if (typeof val === 'string') { try { return JSON.stringify(JSON.parse(val), null, 2) } catch { return val } } return JSON.stringify(val, null, 2) }
</script>
