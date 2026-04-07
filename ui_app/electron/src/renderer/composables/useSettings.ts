import { ref, onMounted } from 'vue'

/**
 * Electron-specific settings persistence using localStorage.
 * (electron-store can be added later via IPC if needed)
 */
const apiBaseUrl = ref('')

export function useSettings() {
  onMounted(() => {
    apiBaseUrl.value = localStorage.getItem('act_api_base_url') || ''
  })

  function setApiBaseUrl(url: string) {
    apiBaseUrl.value = url
    localStorage.setItem('act_api_base_url', url)
  }

  return {
    apiBaseUrl,
    setApiBaseUrl,
  }
}
