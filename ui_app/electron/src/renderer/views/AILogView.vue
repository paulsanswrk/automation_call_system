<template>
  <div>
    <!-- Filter Bar -->
    <div class="filter-row">
      <select v-model="filterChannel" class="setting-input filter-input" @change="applyFilter">
        <option value="">All Channels</option>
        <option v-for="ch in channels" :key="ch.id" :value="ch.channel_name">#{{ch.channel_name}}</option>
      </select>
      <input type="date" v-model="filterDateFrom" class="setting-input filter-input" @change="applyFilter" />
      <input type="date" v-model="filterDateTo" class="setting-input filter-input" @change="applyFilter" />
      <button @click="applyFilter" class="btn" :disabled="loading">Filter</button>
      <div style="flex: 1"></div>
      <button @click="bulkDelete" class="btn btn-danger" :disabled="loading || (!filterChannel && !filterDateFrom)" v-if="isAdmin">
        🗑 Delete All
      </button>
    </div>

    <div v-if="loading && logs.length === 0" class="empty-state">
      <div class="spinner" style="margin: 0 auto;"></div>
    </div>

    <div v-else-if="logs.length === 0" class="empty-state">
      <div class="empty-icon">🤖</div>
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
            <tr v-for="log in logs" :key="log.id" class="pos-row" @click="selectedLog = log">
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
                <button class="delete-btn" @click="deleteLog(log.id)" title="Delete">🗑</button>
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
            <button class="copy-btn" @click="copyText(selectedLog.user_prompt)" title="Copy">📋</button>
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
import { useSystemWS } from '@/composables/useSystemWS'

interface AILog {
  id: number; created_at: string; model: string; user_prompt: string; response: string; tokens_in: number; tokens_out: number; cost_usd: number; is_test: boolean; channel_name?: string
}
interface Channel { id: number; channel_name: string }

const logs = ref<AILog[]>([])
const channels = ref<Channel[]>([])
const loading = ref(true)
const totalCount = ref(0)
const currentPage = ref(1)
const limit = ref(25)
const selectedLog = ref<AILog | null>(null)

const filterChannel = ref('')
const filterDateFrom = ref('')
const filterDateTo = ref('')

const { user } = useAuth()
const isAdmin = computed(() => (user.value?.app_metadata as any)?.role === 'admin')
const totalPages = computed(() => Math.ceil(totalCount.value / limit.value))
const { latestAILog } = useSystemWS()

onMounted(async () => { await fetchData() })

watch(latestAILog, (newLog) => {
  if (newLog && currentPage.value === 1) {
    if (!filterChannel.value || newLog.channel_name === filterChannel.value) { logs.value.unshift(newLog); totalCount.value++; if (logs.value.length > limit.value) logs.value.pop() }
  }
})

async function fetchData(page = 1) {
  loading.value = true
  try {
    let url = `/api/ai-log?page=${page}&limit=${limit.value}`
    if (filterChannel.value) url += `&channel=${encodeURIComponent(filterChannel.value)}`
    if (filterDateFrom.value) url += `&date_from=${filterDateFrom.value}`
    if (filterDateTo.value) url += `&date_to=${filterDateTo.value}`
    const [res, channelsRes] = await Promise.all([apiFetch(url), apiFetch('/api/channels')])
    if (res.ok) { const json = await res.json(); logs.value = json.data || []; totalCount.value = json.total || 0; currentPage.value = json.page }
    if (channelsRes.ok) channels.value = await channelsRes.json()
  } catch (err) { console.error('Failed to fetch AI logs:', err) }
  finally { loading.value = false }
}

async function applyFilter() { await fetchData(1) }

async function bulkDelete() {
  if (!filterChannel.value && !filterDateFrom.value) { alert('Please apply at least one filter.'); return }
  let msg = 'Delete ALL AI logs matching filters:\n'
  if (filterChannel.value) msg += `- Channel: ${filterChannel.value}\n`
  if (filterDateFrom.value) msg += `- From: ${filterDateFrom.value}\n`
  if (filterDateTo.value) msg += `- To: ${filterDateTo.value}\n`
  msg += '\nThis cannot be undone.'
  if (!confirm(msg)) return
  loading.value = true
  try {
    let url = '/api/ai-log?'
    if (filterChannel.value) url += `channel=${encodeURIComponent(filterChannel.value)}&`
    if (filterDateFrom.value) url += `date_from=${filterDateFrom.value}&`
    if (filterDateTo.value) url += `date_to=${filterDateTo.value}`
    const res = await apiFetch(url, { method: 'DELETE' })
    if (res.ok) { const data = await res.json(); alert(`Deleted ${data.count} AI logs.`); await fetchData(1) }
    else { const err = await res.json(); alert('Delete failed: ' + err.error) }
  } catch { alert('Delete failed.') }
  finally { loading.value = false }
}

async function changePage(page: number) { if (page < 1 || page > totalPages.value) return; await fetchData(page) }
async function deleteLog(id: number) { try { const res = await apiFetch(`/api/ai-log/${id}`, { method: 'DELETE' }); if (res.ok) await fetchData(currentPage.value) } catch (err) { console.error('Delete error:', err) } }
function truncate(str: string, len: number) { if (!str) return '—'; if (str.length <= len) return str; return str.substring(0, len) + '...' }
function formatTimeChunk(dStr: string) { const d = new Date(dStr); return `${d.getMonth()+1}/${d.getDate()} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}` }
function formatCost(val: number) { if (!val) return '—'; return `$${val.toFixed(4)}` }
function copyText(text: string) { navigator.clipboard?.writeText(text) }
</script>
