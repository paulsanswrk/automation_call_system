<template>
  <div>




    <!-- Filter Bar -->
    <div class="filter-row">
      <select v-model="filterAction" class="setting-input filter-input action-select" @change="applyFilter">
        <option value="">All Actions</option>
        <option value="PLACE_ORDER">PLACE_ORDER</option>
        <option value="SKIP">SKIP</option>
        <option value="ERROR">ERROR</option>
        <option value="AUTO_SL_BREAKEVEN">AUTO_SL_BREAKEVEN</option>
      </select>
      <DatePicker v-model="filterDates" selectionMode="range" placeholder="Date Range" @update:modelValue="applyFilter" class="filter-input-date" />
      <button @click="applyFilter" class="btn" :disabled="loading">Filter</button>
      <div style="flex: 1"></div>
      <button @click="bulkDelete" class="btn btn-danger" :disabled="loading || (!filterAction && (!filterDates || filterDates.length === 0))" v-if="isAdmin">
        <span class="pi pi-trash" style="margin-right:0.3rem"></span> Delete All
      </button>
    </div>

    <div v-if="loading && actions.length === 0" class="empty-state">
      <div class="spinner" style="margin: 0 auto;"></div>
    </div>

    <div v-else-if="actions.length === 0" class="empty-state">
      <div class="empty-icon pi pi-list"></div>
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
            <tr v-for="action in actions" :key="action.id" class="pos-row" @click="selectedAction = action" style="cursor: pointer;">
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
                <span class="pos-side-badge" :class="action.side === 'LONG' || action.side === 'BUY' ? 'pos-long' : 'pos-short'" v-if="action.side">
                  {{ action.side }}
                </span>
                <span v-else>—</span>
              </td>
              <td class="pos-mono">{{ action.price || '—' }}</td>
              <td class="pos-mono">{{ action.qty || '—' }}</td>
              <td class="pos-mono trunc-cell" style="max-width: 100px">{{ action.order_id || '—' }}</td>
              <td class="trunc-cell" style="max-width: 150px">{{ action.notes || '—' }}</td>
              <td v-if="isAdmin" @click.stop>
                <button class="delete-btn" @click="deleteAction(action.id)" title="Delete Action">
                  <span class="pi pi-trash"></span>
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Pagination Controls -->
      <div class="pagination-controls">
        <button class="google-btn" :disabled="currentPage === 1" @click="changePage(currentPage - 1)" style="padding: 0.5rem 1rem">
          Previous
        </button>
        <span class="page-info">Page {{ currentPage }} of {{ totalPages || 1 }}</span>
        <button class="google-btn" :disabled="currentPage >= totalPages" @click="changePage(currentPage + 1)" style="padding: 0.5rem 1rem">
          Next
        </button>
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
            <tr><td>Action</td><td>
              <span class="action-badge" :class="{
                'place-order': selectedAction.action === 'PLACE_ORDER',
                'skip': selectedAction.action === 'SKIP',
                'error': selectedAction.action === 'ERROR',
                'auto-sl': selectedAction.action === 'AUTO_SL_BREAKEVEN'
              }">{{ selectedAction.action }}</span>
            </td></tr>
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
import DatePicker from 'primevue/datepicker'
import { useSystemWS } from '@/composables/useSystemWS'

interface TradeAction {
  id: number
  created_at: string
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
  request: any
  result: any
  client_id: string
}

const actions = ref<TradeAction[]>([])
const loading = ref(true)
const totalCount = ref(0)
const currentPage = ref(1)
const limit = ref(25)
const selectedAction = ref<TradeAction | null>(null)

const filterAction = ref('')
const filterDates = ref<Date[]>([])

const { user } = useAuth()
// Check Supabase JWT app_metadata for admin role
const isAdmin = computed(() => {
  return (user.value?.app_metadata as any)?.role === 'admin'
})

const totalPages = computed(() => {
  return Math.ceil(totalCount.value / limit.value)
})

const { latestTradeAction } = useSystemWS()

onMounted(async () => {
  await fetchData()
})

watch(latestTradeAction, (newAction) => {
  if (newAction && currentPage.value === 1) {
    // Only prepend if filters aren't restrictive, or if they match
    if (!filterAction.value || newAction.action === filterAction.value) {
      actions.value.unshift(newAction)
      totalCount.value++
      if (actions.value.length > limit.value) actions.value.pop()
    }
  }
})

async function fetchData(page = 1) {
  loading.value = true
  try {
    let url = `/api/trade-actions?page=${page}&limit=${limit.value}`
    if (filterAction.value) {
      url += `&action=${encodeURIComponent(filterAction.value)}`
    }
    if (filterDates.value && filterDates.value[0]) {
      const d = filterDates.value[0]
      const fromStr = `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')}`
      url += `&date_from=${encodeURIComponent(fromStr)}`
    }
    if (filterDates.value && filterDates.value[1]) {
      const d = filterDates.value[1]
      const toStr = `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')}`
      url += `&date_to=${encodeURIComponent(toStr)}`
    }

    const res = await apiFetch(url)
    if (res.ok) {
      const json = await res.json()
      actions.value = json.data || []
      totalCount.value = json.total || 0
      currentPage.value = json.page
    }
  } catch (err) {
    console.error('Failed to fetch trade actions:', err)
  } finally {
    loading.value = false
  }
}

async function applyFilter() {
  await fetchData(1)
}

async function bulkDelete() {
  if (!filterAction.value && (!filterDates.value || filterDates.value.length === 0)) {
    alert("Please apply at least one filter before bulk deleting.")
    return
  }
  
  let msg = "Are you sure you want to delete ALL actions matching the filters:\n"
  if (filterAction.value) msg += `- Action: ${filterAction.value}\n`
  if (filterDates.value && filterDates.value[0]) msg += `- From: ${filterDates.value[0].toLocaleDateString()}\n`
  if (filterDates.value && filterDates.value[1]) msg += `- To: ${filterDates.value[1].toLocaleDateString()}\n`
  msg += "\nThis cannot be undone."
  
  if (!confirm(msg)) return

  loading.value = true
  try {
    let url = '/api/trade-actions?'
    if (filterAction.value) url += `action=${encodeURIComponent(filterAction.value)}&`
    if (filterDates.value && filterDates.value[0]) {
      const d = filterDates.value[0]
      url += `date_from=${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')}&`
    }
    if (filterDates.value && filterDates.value[1]) {
      const d = filterDates.value[1]
      url += `date_to=${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')}`
    }

    const res = await apiFetch(url, { method: 'DELETE' })
    if (res.ok) {
      const data = await res.json()
      alert(`Deleted ${data.count} actions.`)
      await fetchData(1)
    } else {
      const err = await res.json()
      alert("Delete failed: " + err.error)
    }
  } catch (e) {
    console.error(e)
    alert("Delete failed.")
  } finally {
    loading.value = false
  }
}

async function changePage(page: number) {
  if (page < 1 || page > totalPages.value) return
  await fetchData(page)
}

async function deleteAction(id: number) {
  try {
    const res = await apiFetch(`/api/trade-actions/${id}`, { method: 'DELETE' })
    if (res.ok) {
      await fetchData(currentPage.value)
    } else {
      console.error('Failed to delete trade action', await res.text())
    }
  } catch (err) {
    console.error('Delete error:', err)
  }
}

function formatTimeChunk(dStr: string) {
  const d = new Date(dStr)
  return `${d.getMonth()+1}/${d.getDate()} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`
}

function formatJSON(val: any) {
  if (!val) return ''
  if (typeof val === 'string') {
    try { return JSON.stringify(JSON.parse(val), null, 2) } catch { return val }
  }
  return JSON.stringify(val, null, 2)
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
  max-width: 200px;
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

.action-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.25rem 0.65rem;
  border-radius: 6px;
  font-size: 0.75rem;
  font-weight: 600;
}
.action-badge.place-order {
  background: rgba(34, 197, 94, 0.12);
  color: var(--green-badge);
  border: 1px solid rgba(34, 197, 94, 0.25);
}
.action-badge.skip {
  background: rgba(245, 158, 11, 0.12);
  color: var(--amber-badge);
  border: 1px solid rgba(245, 158, 11, 0.25);
}
.action-badge.error {
  background: rgba(239, 68, 68, 0.12);
  color: var(--red-badge);
  border: 1px solid rgba(239, 68, 68, 0.25);
}
.action-badge.auto-sl {
  background: rgba(59, 130, 246, 0.12);
  color: #3b82f6;
  border: 1px solid rgba(59, 130, 246, 0.25);
}

.trunc-cell {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--text-color-secondary);
  font-size: 0.8rem;
}
.pagination-controls {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 1.5rem;
  margin-top: 1rem;
}
.page-info {
  font-size: 0.9rem;
  color: var(--text-color-secondary);
  font-weight: 500;
}
.code-block {
  background: #000;
  padding: 1rem;
  border-radius: 8px;
  font-family: 'JetBrains Mono', monospace;
  font-size: 0.85rem;
  color: var(--text-color);
  overflow-x: auto;
  white-space: pre-wrap;
  margin-top: 0.5rem;
}
.delete-btn {
  background: none;
  border: none;
  color: var(--text-color-secondary);
  cursor: pointer;
  padding: 0.25rem;
  border-radius: 4px;
  transition: all 0.15s ease;
}
.delete-btn:hover {
  color: var(--red-badge);
  background: rgba(239, 68, 68, 0.1);
}
:deep(.filter-input-date .p-inputtext) {
  background: var(--surface-card);
  border: 1px solid var(--surface-border);
  color: var(--text-color);
  border-radius: 8px;
  font-size: 0.85rem;
  padding: 0.45rem 0.75rem;
}
:deep(.filter-input-date.p-datepicker) {
  max-width: 250px;
}
</style>
