<template>
  <div>
    <div class="feed-header">
      <button class="add-account-btn" @click="showAddModal = true">
        <span class="pi pi-plus"></span>
        Add Account
      </button>
    </div>



    <!-- Loading -->
    <div v-if="loading && accounts.length === 0" class="empty-state">
      <div class="spinner" style="margin: 0 auto;"></div>
    </div>

    <!-- Empty -->
    <div v-else-if="accounts.length === 0" class="empty-state">
      <div class="empty-icon pi pi-wallet"></div>
      <h2>No Exchange Accounts</h2>
      <p>Connect an exchange by adding your API keys. Keys are encrypted at rest.</p>
      <button class="empty-add-btn" @click="showAddModal = true">
        <span class="pi pi-plus"></span>
        Add Your First Account
      </button>
    </div>

    <!-- Accounts Grid -->
    <div v-else class="accounts-grid">
      <div
        v-for="acc in accounts"
        :key="acc.id"
        class="account-card"
        :class="'exchange-' + acc.exchange_type"
      >
        <div class="account-card-header">
          <div class="account-exchange-row">
            <span class="exchange-icon" :class="'icon-' + acc.exchange_type">
              {{ exchangeIcon(acc.exchange_type) }}
            </span>
            <div class="account-info">
              <span class="account-label">{{ acc.label }}</span>
              <span class="account-exchange-name">{{ formatExchangeName(acc.exchange_type) }}</span>
            </div>
            <div class="badges-group">
              <span class="account-status-badge" :class="acc.is_active ? 'status-active' : 'status-inactive'">
                {{ acc.is_active ? 'Active' : 'Inactive' }}
              </span>
              <span v-if="acc.is_active" class="connection-badge" :class="acc.is_connected ? 'conn-connected' : 'conn-error'">
                <span class="status-dot"></span>
                {{ acc.is_connected ? 'Connected' : 'Error' }}
              </span>
            </div>
          </div>
        </div>

        <div class="account-details">
          <div class="detail-row" v-if="acc.available_balance">
            <span class="detail-label">Balance</span>
            <span class="detail-value mono" :class="{ 'positive-balance': Number(acc.available_balance) > 0 }">
              ${{ acc.available_balance }}
            </span>
          </div>
          <div class="detail-row">
            <span class="detail-label">API Key</span>
            <span class="detail-value mono">{{ acc.api_key_masked }}</span>
          </div>
          <div class="detail-row">
            <span class="detail-label">Added</span>
            <span class="detail-value">{{ formatDate(acc.created_at) }}</span>
          </div>
          <div v-if="acc.last_error" class="account-error-banner">
            <span class="pi pi-exclamation-triangle error-icon"></span>
            <span class="error-text">{{ acc.last_error }}</span>
          </div>
        </div>

        <div class="account-card-footer">
          <div class="encryption-badge">
            <span class="pi pi-lock"></span>
            Encrypted
          </div>
          <button class="delete-btn" @click="deleteAccount(acc.id, acc.label)" title="Remove account">
            <span class="pi pi-trash"></span>
          </button>
        </div>
      </div>
    </div>

    <!-- Add Account Modal -->
    <div v-if="showAddModal" class="detail-overlay" @click.self="closeModal">
      <div class="add-modal">
        <div class="modal-header">
          <h2>Add Exchange Account</h2>
          <button class="detail-close" @click="closeModal">
            <span class="pi pi-times"></span>
          </button>
        </div>

        <div class="modal-info">
          <span class="pi pi-shield"></span>
          <span>Your API keys are encrypted with AES-256 before storage. They are never exposed in plaintext.</span>
        </div>

        <form @submit.prevent="submitAccount" class="add-form">
          <div class="form-group">
            <label class="form-label">Exchange</label>
            <div class="exchange-selector">
              <button
                v-for="ex in exchangeOptions"
                :key="ex.value"
                type="button"
                class="exchange-option"
                :class="{ selected: form.exchange_type === ex.value }"
                @click="form.exchange_type = ex.value"
              >
                <span class="exchange-option-icon">{{ ex.icon }}</span>
                <span class="exchange-option-name">{{ ex.label }}</span>
              </button>
            </div>
          </div>

          <div class="form-group">
            <label class="form-label" for="add-label">Label</label>
            <input
              id="add-label"
              type="text"
              class="form-input"
              v-model="form.label"
              placeholder="e.g. My Main Account"
              required
              maxlength="100"
            />
          </div>

          <div class="form-group">
            <label class="form-label" for="add-api-key">API Key</label>
            <div class="input-with-toggle">
              <input
                id="add-api-key"
                :type="showApiKey ? 'text' : 'password'"
                class="form-input"
                v-model="form.api_key"
                placeholder="Paste your API key"
                required
                autocomplete="off"
              />
              <button type="button" class="toggle-visibility" @click="showApiKey = !showApiKey">
                <span class="pi" :class="showApiKey ? 'pi-eye-slash' : 'pi-eye'"></span>
              </button>
            </div>
          </div>

          <div class="form-group">
            <label class="form-label" for="add-secret-key">Secret Key</label>
            <div class="input-with-toggle">
              <input
                id="add-secret-key"
                :type="showSecretKey ? 'text' : 'password'"
                class="form-input"
                v-model="form.secret_key"
                placeholder="Paste your secret key"
                required
                autocomplete="off"
              />
              <button type="button" class="toggle-visibility" @click="showSecretKey = !showSecretKey">
                <span class="pi" :class="showSecretKey ? 'pi-eye-slash' : 'pi-eye'"></span>
              </button>
            </div>
          </div>

          <div class="form-actions">
            <button type="button" class="btn-cancel" @click="closeModal">Cancel</button>
            <button
              type="submit"
              class="btn-submit"
              :disabled="submitting || !formValid"
            >
              <span v-if="submitting" class="spinner-small"></span>
              <span v-else class="pi pi-plus"></span>
              {{ submitting ? 'Adding...' : 'Add Account' }}
            </button>
          </div>

          <div v-if="submitError" class="form-error">
            <span class="pi pi-exclamation-triangle"></span>
            {{ submitError }}
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { apiFetch } from '@/lib/api'

interface ExchangeAccountResponse {
  id: number
  exchange_type: string
  label: string
  api_key_masked: string
  is_active: boolean
  is_connected: boolean
  last_error: string
  available_balance?: string
  created_at: string
}

const accounts = ref<ExchangeAccountResponse[]>([])
const loading = ref(true)
const showAddModal = ref(false)
const submitting = ref(false)
const submitError = ref('')
const showApiKey = ref(false)
const showSecretKey = ref(false)

const form = ref({
  exchange_type: 'bitunix',
  label: '',
  api_key: '',
  secret_key: '',
})

const exchangeOptions = [
  { value: 'bitunix', label: 'BitUnix', icon: '⚡' },
  { value: 'phemex', label: 'Phemex', icon: '🔷' },
]

const formValid = computed(() => {
  return form.value.exchange_type &&
    form.value.label.trim() &&
    form.value.api_key.trim() &&
    form.value.secret_key.trim()
})


onMounted(async () => {
  await fetchAccounts()
})

async function fetchAccounts() {
  loading.value = true
  try {
    const res = await apiFetch('/api/exchange-accounts')
    if (res.ok) {
      accounts.value = await res.json()
    }
  } catch (err) {
    console.error('Failed to fetch exchange accounts:', err)
  } finally {
    loading.value = false
  }
}

function formatExchangeName(type: string): string {
  const names: Record<string, string> = { bitunix: 'BitUnix', phemex: 'Phemex' }
  return names[type] || type
}

function exchangeIcon(type: string): string {
  const icons: Record<string, string> = { bitunix: '⚡', phemex: '🔷' }
  return icons[type] || '🔗'
}

function formatDate(dateStr: string) {
  const d = new Date(dateStr)
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

function closeModal() {
  showAddModal.value = false
  form.value = { exchange_type: 'bitunix', label: '', api_key: '', secret_key: '' }
  submitError.value = ''
  showApiKey.value = false
  showSecretKey.value = false
}

async function submitAccount() {
  submitting.value = true
  submitError.value = ''
  try {
    const res = await apiFetch('/api/exchange-accounts', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(form.value),
    })
    if (res.ok) {
      closeModal()
      await fetchAccounts()
    } else {
      const data = await res.json()
      submitError.value = data.error || 'Failed to add account'
    }
  } catch (err) {
    submitError.value = 'Network error. Please try again.'
    console.error('Submit account error:', err)
  } finally {
    submitting.value = false
  }
}

async function deleteAccount(id: number, label: string) {
  if (!confirm(`Remove "${label}"? This cannot be undone.`)) return
  try {
    const res = await apiFetch(`/api/exchange-accounts/${id}`, { method: 'DELETE' })
    if (res.ok) {
      await fetchAccounts()
    }
  } catch (err) {
    console.error('Delete account error:', err)
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

.add-account-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.6rem 1.25rem;
  border-radius: 10px;
  border: none;
  background: linear-gradient(135deg, #6366f1, #818cf8);
  color: white;
  font-size: 0.85rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
  box-shadow: 0 2px 8px rgba(99, 102, 241, 0.3);
}

.add-account-btn:hover {
  transform: translateY(-1px);
  box-shadow: 0 4px 16px rgba(99, 102, 241, 0.4);
}

/* Summary */
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

/* Empty */
.empty-add-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  margin-top: 1.5rem;
  padding: 0.75rem 1.5rem;
  border-radius: 10px;
  border: none;
  background: linear-gradient(135deg, #6366f1, #818cf8);
  color: white;
  font-size: 0.9rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
  box-shadow: 0 2px 8px rgba(99, 102, 241, 0.3);
}

.empty-add-btn:hover {
  transform: translateY(-1px);
  box-shadow: 0 4px 16px rgba(99, 102, 241, 0.4);
}

/* Accounts Grid */
.accounts-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(380px, 1fr));
  gap: 1rem;
}

.account-card {
  background: var(--surface-card);
  border: 1px solid var(--surface-border);
  border-radius: 14px;
  padding: 1.25rem;
  transition: all 0.2s;
  display: flex;
  flex-direction: column;
  gap: 1rem;
  border-left: 3px solid var(--surface-border);
}

.account-card:hover {
  border-color: rgba(99, 102, 241, 0.3);
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.25);
}

.account-card.exchange-bitunix {
  border-left-color: #22c55e;
}

.account-card.exchange-phemex {
  border-left-color: #6366f1;
}

/* Card Header */
.account-exchange-row {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.exchange-icon {
  width: 42px;
  height: 42px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.25rem;
  flex-shrink: 0;
}

.icon-bitunix {
  background: rgba(34, 197, 94, 0.12);
}

.icon-phemex {
  background: rgba(99, 102, 241, 0.12);
}

.account-info {
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
  flex: 1;
  min-width: 0;
}

.account-label {
  font-size: 1rem;
  font-weight: 700;
  color: var(--text-color);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.account-exchange-name {
  font-size: 0.78rem;
  color: var(--text-color-secondary);
  font-weight: 500;
}

.account-status-badge {
  display: inline-flex;
  align-items: center;
  padding: 0.2rem 0.6rem;
  border-radius: 100px;
  font-size: 0.7rem;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  flex-shrink: 0;
}

.status-active {
  background: rgba(34, 197, 94, 0.12);
  border: 1px solid rgba(34, 197, 94, 0.3);
  color: var(--green-badge);
}

.status-inactive {
  background: rgba(148, 163, 184, 0.1);
  border: 1px solid rgba(148, 163, 184, 0.2);
  color: var(--text-color-secondary);
}

.badges-group {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.connection-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  padding: 0.2rem 0.6rem;
  border-radius: 100px;
  font-size: 0.7rem;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  flex-shrink: 0;
}

.conn-connected {
  background: rgba(34, 197, 94, 0.1);
  color: var(--green-badge);
}

.conn-connected .status-dot {
  background: var(--green-badge);
  box-shadow: 0 0 6px var(--green-badge);
}

.conn-error {
  background: rgba(239, 68, 68, 0.1);
  color: var(--red-badge);
}

.conn-error .status-dot {
  background: var(--red-badge);
  box-shadow: 0 0 6px var(--red-badge);
}

.status-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  display: inline-block;
}

/* Details */
.account-details {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  padding: 0.75rem;
  background: rgba(15, 23, 42, 0.4);
  border-radius: 10px;
}

.detail-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.detail-label {
  font-size: 0.78rem;
  font-weight: 600;
  color: var(--text-color-secondary);
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.detail-value {
  font-size: 0.85rem;
  color: var(--text-color);
}

.detail-value.mono {
  font-family: 'JetBrains Mono', 'Fira Code', monospace;
  letter-spacing: 0.05em;
  color: var(--primary-color-hover);
}

.positive-balance {
  color: var(--green-badge) !important;
  font-weight: 700;
}

.account-error-banner {
  margin-top: 0.5rem;
  padding: 0.65rem 0.75rem;
  background: rgba(239, 68, 68, 0.08);
  border: 1px solid rgba(239, 68, 68, 0.2);
  border-radius: 8px;
  display: flex;
  align-items: flex-start;
  gap: 0.5rem;
}

.error-icon {
  color: var(--red-badge);
  font-size: 0.85rem;
  margin-top: 0.15rem;
  flex-shrink: 0;
}

.error-text {
  font-size: 0.8rem;
  color: var(--red-badge);
  line-height: 1.4;
  word-break: break-word;
}

/* Card Footer */
.account-card-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding-top: 0.5rem;
  border-top: 1px solid var(--surface-border);
}

.encryption-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  font-size: 0.72rem;
  color: var(--green-badge);
  opacity: 0.7;
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

/* Modal */
.add-modal {
  background: var(--surface-card);
  border: 1px solid var(--surface-border);
  border-radius: 16px;
  max-width: 520px;
  width: 100%;
  max-height: 90vh;
  overflow-y: auto;
  padding: 2rem;
  box-shadow: 0 25px 50px rgba(0, 0, 0, 0.5);
  animation: modalIn 0.2s ease;
}

@keyframes modalIn {
  from { opacity: 0; transform: scale(0.95) translateY(10px); }
  to { opacity: 1; transform: scale(1) translateY(0); }
}

.modal-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1.25rem;
}

.modal-header h2 {
  font-size: 1.25rem;
  font-weight: 700;
}

.modal-info {
  display: flex;
  align-items: flex-start;
  gap: 0.65rem;
  padding: 0.85rem 1rem;
  border-radius: 10px;
  background: rgba(34, 197, 94, 0.06);
  border: 1px solid rgba(34, 197, 94, 0.15);
  font-size: 0.8rem;
  color: var(--text-color-secondary);
  margin-bottom: 1.5rem;
  line-height: 1.45;
}

.modal-info .pi {
  color: var(--green-badge);
  font-size: 1rem;
  margin-top: 0.1rem;
  flex-shrink: 0;
}

/* Form */
.add-form {
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.form-label {
  font-size: 0.78rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-color-secondary);
}

.exchange-selector {
  display: flex;
  gap: 0.75rem;
}

.exchange-option {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 0.65rem;
  padding: 0.85rem 1rem;
  border-radius: 10px;
  border: 2px solid var(--surface-border);
  background: var(--surface-ground);
  color: var(--text-color-secondary);
  cursor: pointer;
  transition: all 0.2s;
}

.exchange-option:hover {
  border-color: rgba(99, 102, 241, 0.3);
  background: rgba(99, 102, 241, 0.05);
}

.exchange-option.selected {
  border-color: var(--primary-color);
  background: rgba(99, 102, 241, 0.08);
  color: var(--text-color);
  box-shadow: 0 0 0 1px var(--primary-color);
}

.exchange-option-icon {
  font-size: 1.25rem;
}

.exchange-option-name {
  font-size: 0.9rem;
  font-weight: 600;
}

.form-input {
  background: var(--surface-ground);
  border: 1px solid var(--surface-border);
  border-radius: 10px;
  color: var(--text-color);
  padding: 0.65rem 0.85rem;
  font-size: 0.88rem;
  width: 100%;
  transition: border-color 0.2s;
}

.form-input:focus {
  outline: none;
  border-color: var(--primary-color);
  box-shadow: 0 0 0 2px rgba(99, 102, 241, 0.15);
}

.form-input::placeholder {
  color: var(--text-color-secondary);
  opacity: 0.5;
}

.input-with-toggle {
  position: relative;
  display: flex;
  align-items: center;
}

.input-with-toggle .form-input {
  padding-right: 2.75rem;
}

.toggle-visibility {
  position: absolute;
  right: 0.65rem;
  background: none;
  border: none;
  color: var(--text-color-secondary);
  cursor: pointer;
  padding: 0.25rem;
  opacity: 0.5;
  transition: opacity 0.15s;
}

.toggle-visibility:hover {
  opacity: 1;
}

.form-actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.75rem;
  margin-top: 0.5rem;
}

.btn-cancel {
  padding: 0.6rem 1.25rem;
  border-radius: 10px;
  border: 1px solid var(--surface-border);
  background: transparent;
  color: var(--text-color-secondary);
  font-size: 0.85rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.15s;
}

.btn-cancel:hover {
  background: rgba(99, 102, 241, 0.05);
  color: var(--text-color);
}

.btn-submit {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.6rem 1.5rem;
  border-radius: 10px;
  border: none;
  background: linear-gradient(135deg, #6366f1, #818cf8);
  color: white;
  font-size: 0.85rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
  box-shadow: 0 2px 8px rgba(99, 102, 241, 0.3);
}

.btn-submit:hover:not(:disabled) {
  transform: translateY(-1px);
  box-shadow: 0 4px 16px rgba(99, 102, 241, 0.4);
}

.btn-submit:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.spinner-small {
  width: 14px;
  height: 14px;
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-top-color: white;
  border-radius: 50%;
  animation: spin 0.6s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.form-error {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.75rem 1rem;
  border-radius: 8px;
  background: rgba(239, 68, 68, 0.08);
  border: 1px solid rgba(239, 68, 68, 0.2);
  color: var(--red-badge);
  font-size: 0.82rem;
}

/* Responsive */
@media (max-width: 768px) {
  .accounts-grid {
    grid-template-columns: 1fr;
  }

  .pos-summary {
    flex-wrap: wrap;
  }

  .pos-summary-card {
    min-width: calc(50% - 0.5rem);
  }

  .add-modal {
    margin: 1rem;
    max-height: calc(100vh - 2rem);
  }

  .exchange-selector {
    flex-direction: column;
  }
}
</style>
