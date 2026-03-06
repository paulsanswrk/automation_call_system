import { ref } from 'vue'
import { supabase } from '@/lib/supabase'

interface SystemWSEvent {
  event_type: string
  data: any
}

// Global state for real-time data
const isConnected = ref(false)
const unreadNotificationsCount = ref(0)
const latestDiscordMessage = ref<any>(null)
const latestTradeAction = ref<any>(null)
const latestAILog = ref<any>(null)
const updateAvailable = ref<string | null>(null)
const channelHeartbeats = ref<Record<string, string>>({})

let ws: WebSocket | null = null
let reconnectTimer: number | null = null

export function useSystemWS() {
  async function connectSystemWebSocket() {
    if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
      return // Already connected or connecting
    }

    const { data: { session } } = await supabase.auth.getSession()
    if (!session?.access_token) return

    const API_BASE = import.meta.env.VITE_API_BASE_URL ?? ''
    const wsBase = API_BASE
      ? API_BASE.replace(/^http/, 'ws')
      : `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}`
    
    const wsUrl = `${wsBase}/api/system/ws?token=${encodeURIComponent(session.access_token)}`

    ws = new WebSocket(wsUrl)

    ws.onopen = () => {
      isConnected.value = true
    }

    ws.onmessage = (event) => {
      try {
        const msg: SystemWSEvent = JSON.parse(event.data)
        
        if (msg.event_type === 'channel_heartbeat' && msg.data) {
          const { channel_name, timestamp } = msg.data
          channelHeartbeats.value[channel_name] = timestamp
        } else if (msg.event_type === 'new_vue_build') {
          updateAvailable.value = msg.data.build || 'New Update Available'
        } else if (msg.event_type === 'new_discord_message') {
          latestDiscordMessage.value = msg.data
          unreadNotificationsCount.value++
        } else if (msg.event_type === 'new_trade_action') {
          latestTradeAction.value = msg.data
        } else if (msg.event_type === 'new_ai_log') {
          latestAILog.value = msg.data
        }
      } catch (err) {
        console.error('[SystemWS] Error parsing message', err)
      }
    }

    ws.onclose = () => {
      isConnected.value = false
      ws = null
      if (reconnectTimer) clearTimeout(reconnectTimer)
      reconnectTimer = window.setTimeout(connectSystemWebSocket, 5000)
    }

    ws.onerror = (err) => {
      console.error('[SystemWS] WebSocket Error', err)
    }
  }

  function disconnect() {
    if (reconnectTimer) {
      clearTimeout(reconnectTimer)
      reconnectTimer = null
    }
    if (ws) {
      ws.onclose = null
      ws.close()
      ws = null
    }
    isConnected.value = false
  }

  function resetUnreadNotifications() {
    unreadNotificationsCount.value = 0
  }

  return {
    isConnected,
    unreadNotificationsCount,
    latestDiscordMessage,
    latestTradeAction,
    latestAILog,
    updateAvailable,
    channelHeartbeats,
    connectSystemWebSocket,
    disconnect,
    resetUnreadNotifications
  }
}
