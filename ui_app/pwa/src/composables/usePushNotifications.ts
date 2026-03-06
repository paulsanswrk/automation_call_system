import { ref, onMounted } from 'vue'
import { apiFetch } from '@/lib/api'

const VAPID_PUBLIC_KEY = import.meta.env.VITE_VAPID_PUBLIC_KEY

const isSupported = ref(false)
const isSubscribed = ref(false)
const isLoading = ref(false)

/**
 * Convert a URL-safe base64 string to a Uint8Array (for applicationServerKey).
 */
function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')
  const rawData = window.atob(base64)
  const outputArray = new Uint8Array(rawData.length)
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i)
  }
  return outputArray
}

/**
 * Composable for managing Web Push notification subscriptions.
 */
export function usePushNotifications() {
  onMounted(async () => {
    isSupported.value = 'serviceWorker' in navigator && 'PushManager' in window

    if (!isSupported.value) return

    // Check if already subscribed
    try {
      const registration = await navigator.serviceWorker.ready
      const subscription = await registration.pushManager.getSubscription()
      isSubscribed.value = !!subscription
    } catch (err) {
      console.warn('Failed to check push subscription:', err)
    }
  })

  async function subscribe() {
    if (!isSupported.value || isLoading.value) return

    isLoading.value = true
    try {
      // 1. Request notification permission (must be from user gesture)
      const permission = await Notification.requestPermission()
      if (permission !== 'granted') {
        console.log('Notification permission denied')
        return
      }

      // 2. Get the service worker registration
      const registration = await navigator.serviceWorker.ready

      // 3. Subscribe to push
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY).buffer as ArrayBuffer,
      })

      // 4. Send subscription to our Go backend
      const subJSON = subscription.toJSON()
      const response = await apiFetch('/api/push/subscribe', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          endpoint: subJSON.endpoint,
          keys_p256dh: subJSON.keys?.p256dh ?? '',
          keys_auth: subJSON.keys?.auth ?? '',
        }),
      })

      if (response.ok) {
        isSubscribed.value = true
        console.log('Push subscription saved')
      } else {
        console.error('Failed to save push subscription:', await response.text())
      }
    } catch (err) {
      console.error('Push subscription error:', err)
    } finally {
      isLoading.value = false
    }
  }

  async function unsubscribe() {
    if (isLoading.value) return

    isLoading.value = true
    try {
      const registration = await navigator.serviceWorker.ready
      const subscription = await registration.pushManager.getSubscription()

      if (subscription) {
        // Tell our backend to remove the subscription
        const subJSON = subscription.toJSON()
        await apiFetch('/api/push/subscribe', {
          method: 'DELETE',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ endpoint: subJSON.endpoint }),
        })

        // Unsubscribe from browser
        await subscription.unsubscribe()
      }

      isSubscribed.value = false
      console.log('Push unsubscribed')
    } catch (err) {
      console.error('Push unsubscribe error:', err)
    } finally {
      isLoading.value = false
    }
  }

  async function toggleSubscription() {
    if (isSubscribed.value) {
      await unsubscribe()
    } else {
      await subscribe()
    }
  }

  return {
    isSupported,
    isSubscribed,
    isLoading,
    subscribe,
    unsubscribe,
    toggleSubscription,
  }
}
