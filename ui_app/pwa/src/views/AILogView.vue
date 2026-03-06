<template>
  <div>




    <!-- Filter Bar -->
    <div class="filter-row">
      <select v-model="filterChannel" class="setting-input filter-input action-select" @change="applyFilter">
        <option value="">All Channels</option>
        <option v-for="ch in channels" :key="ch.id" :value="ch.channel_name">#{{ch.channel_name}}</option>
      </select>
      <DatePicker v-model="filterDates" selectionMode="range" placeholder="Date Range" @update:modelValue="applyFilter" class="filter-input-date" />
      <button @click="applyFilter" class="btn" :disabled="loading">Filter</button>
      <div style="flex: 1"></div>
      <button @click="bulkDelete" class="btn btn-danger" :disabled="loading || (!filterChannel && (!filterDates || filterDates.length === 0))" v-if="isAdmin">
        <span class="pi pi-trash" style="margin-right:0.3rem"></span> Delete All
      </button>
    </div>

    <div v-if="loading && logs.length === 0" class="empty-state">
      <div class="spinner" style="margin: 0 auto;"></div>
    </div>

    <div v-else-if="logs.length === 0" class="empty-state">
      <div class="empty-icon pi pi-file"></div>
      <h2>No AI Logs</h2>
      <p>AI processing logs will appear here.</p>
    </div>

    <div v-else>
      <div class="pos-table-wrap" style="margin-bottom: 1rem;">
        <table class="pos-table">
          <thead>
            <tr>
              <th>Time</th>
              <th>Model</th>
              <th>Tokens In</th>
              <th>Tokens Out</th>
              <th>Cost (USD)</th>
              <th>User Prompt</th>
              <th>Response</th>
              <th v-if="isAdmin">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="log in logs" :key="log.id" class="pos-row" @click="selectedLog = log" style="cursor: pointer;">
              <td style="white-space: nowrap">{{ formatTimeChunk(log.created_at) }}</td>
              <td><span class="pos-margin-badge">{{ log.model }}</span></td>
              <td class="pos-mono">{{ log.tokens_in || '—' }}</td>
              <td class="pos-mono">{{ log.tokens_out || '—' }}</td>
              <td class="pos-mono" :class="log.cost_usd && log.cost_usd > 0 ? 'pnl-negative' : ''">
                 {{ formatCost(log.cost_usd) }}
              </td>
              <td class="trunc-cell">{{ truncate(log.user_prompt, 40) }}</td>
              <td class="trunc-cell">{{ truncate(log.response, 40) }}</td>
              <td v-if="isAdmin" @click.stop>
                <button class="delete-btn" @click="deleteLog(log.id)" title="Delete Log">
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
    <div v-if="selectedLog" class="detail-overlay" @click.self="selectedLog = null">
      <div class="detail-panel" style="max-width: 800px;">
        <button class="detail-close" @click="selectedLog = null">✕</button>

        <div class="detail-section">
          <h3>Log Details</h3>
          <table class="detail-table">
            <tr><td>Time</td><td>{{ new Date(selectedLog.created_at).toLocaleString() }}</td></tr>
            <tr><td>Model</td><td>{{ selectedLog.model }}</td></tr>
            <tr><td>Tokens In</td><td>{{ selectedLog.tokens_in }}</td></tr>
            <tr><td>Tokens Out</td><td>{{ selectedLog.tokens_out }}</td></tr>
            <tr><td>Cost</td><td>${{ selectedLog.cost_usd }}</td></tr>
          </table>
        </div>
        
        <div class="detail-section" v-if="selectedLog.user_prompt">
          <div style="display: flex; justify-content: space-between; align-items: center;">
            <h3 style="margin: 0;">User Prompt</h3>
            <button class="copy-btn" @click="copyPrompt(selectedLog.user_prompt)" title="Copy Prompt">
              <span class="pi pi-copy"></span>
            </button>
          </div>
          <pre class="code-block">{{ selectedLog.user_prompt }}</pre>
        </div>

        <div class="detail-section" v-if="selectedLog.response">
          <h3>AI Response</h3>
          <pre class="code-block">{{ selectedLog.response }}</pre>
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

interface AILog {
  id: number
  created_at: string
  model: string
  user_prompt: string
  response: string
  tokens_in: number
  tokens_out: number
  cost_usd: number
  is_test: boolean
}

interface Channel {
  id: number
  channel_name: string
}

const logs = ref<AILog[]>([])
const channels = ref<Channel[]>([])
const loading = ref(true)
const totalCount = ref(0)
const currentPage = ref(1)
const limit = ref(25)
const selectedLog = ref<AILog | null>(null)

const filterChannel = ref('')
const filterDates = ref<Date[]>([])

const { user } = useAuth()
// Check Supabase JWT app_metadata for admin role
const isAdmin = computed(() => {
  return (user.value?.app_metadata as any)?.role === 'admin'
})

const totalPages = computed(() => {
  return Math.ceil(totalCount.value / limit.value)
})

const { latestAILog } = useSystemWS()

onMounted(async () => {
  await fetchData()
})

watch(latestAILog, (newLog) => {
  if (newLog && currentPage.value === 1) {
    if (!filterChannel.value || newLog.channel_name === filterChannel.value) {
      logs.value.unshift(newLog)
      totalCount.value++
      if (logs.value.length > limit.value) logs.value.pop()
    }
  }
})

async function fetchData(page = 1) {
  loading.value = true
  try {
    let url = `/api/ai-log?page=${page}&limit=${limit.value}`
    if (filterChannel.value) {
      url += `&channel=${encodeURIComponent(filterChannel.value)}`
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

    const [res, channelsRes] = await Promise.all([
      apiFetch(url),
      apiFetch('/api/channels')
    ])
    if (res.ok) {
      const json = await res.json()
      logs.value = json.data || []
      totalCount.value = json.total || 0
      currentPage.value = json.page
    }
    if (channelsRes.ok) channels.value = await channelsRes.json()
  } catch (err) {
    console.error('Failed to fetch AI logs:', err)
  } finally {
    loading.value = false
  }
}

async function applyFilter() {
  await fetchData(1)
}

async function bulkDelete() {
  if (!filterChannel.value && (!filterDates.value || filterDates.value.length === 0)) {
    alert("Please apply at least one filter before bulk deleting.")
    return
  }
  
  let msg = "Are you sure you want to delete ALL AI logs matching the filters:\n"
  if (filterChannel.value) msg += `- Channel: ${filterChannel.value}\n`
  if (filterDates.value && filterDates.value[0]) msg += `- From: ${filterDates.value[0].toLocaleDateString()}\n`
  if (filterDates.value && filterDates.value[1]) msg += `- To: ${filterDates.value[1].toLocaleDateString()}\n`
  msg += "\nThis cannot be undone."
  
  if (!confirm(msg)) return

  loading.value = true
  try {
    let url = '/api/ai-log?'
    if (filterChannel.value) url += `channel=${encodeURIComponent(filterChannel.value)}&`
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
      alert(`Deleted ${data.count} AI logs.`)
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

async function deleteLog(id: number) {
  try {
    const res = await apiFetch(`/api/ai-log/${id}`, { method: 'DELETE' })
    if (res.ok) {
      await fetchData(currentPage.value)
    } else {
      console.error('Failed to delete ai log', await res.text())
    }
  } catch (err) {
    console.error('Delete error:', err)
  }
}

function truncate(str: string, len: number) {
  if (!str) return '—'
  if (str.length <= len) return str
  return str.substring(0, len) + '...'
}

function formatTimeChunk(dStr: string) {
  const d = new Date(dStr)
  return `${d.getMonth()+1}/${d.getDate()} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`
}

function formatCost(val: number) {
  if (!val) return '—'
  return `$${val.toFixed(4)}`
}

function copyPrompt(text: string) {
  if (navigator.clipboard) {
    navigator.clipboard.writeText(text);
  }
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
.pnl-negative {
  color: #ef4444;
}
.trunc-cell {
  max-width: 200px;
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
.copy-btn {
  background: none;
  border: none;
  color: var(--text-color-secondary);
  cursor: pointer;
  padding: 0.25rem;
  border-radius: 4px;
  transition: all 0.15s ease;
}
.copy-btn:hover {
  color: var(--primary-color);
  background: rgba(99, 102, 241, 0.1);
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
