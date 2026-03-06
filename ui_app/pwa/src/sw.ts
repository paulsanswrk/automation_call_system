/// <reference lib="webworker" />
import { precacheAndRoute } from 'workbox-precaching'

declare const self: ServiceWorkerGlobalScope

// Workbox precaching — vite-plugin-pwa injects the manifest here
precacheAndRoute(self.__WB_MANIFEST)

// ── Handle skip waiting ──────────────────────────────────────
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting()
  }
})

// ── Push notification handler ────────────────────────────────
self.addEventListener('push', (event) => {
  let data: { title?: string; body?: string; url?: string } = {}

  try {
    data = event.data?.json() ?? {}
  } catch {
    data = { body: event.data?.text() ?? 'New trade activity' }
  }

  const title = data.title ?? 'ACT Trading'
  const options: NotificationOptions = {
    body: data.body ?? 'New trade activity',
    icon: '/icon-192.png',
    badge: '/icon-192.png',
    data: { url: data.url ?? '/' },
    tag: 'act-trade-' + Date.now(), // unique so each notification shows
  }

  event.waitUntil(self.registration.showNotification(title, options))
})

// ── Notification click — open / focus the app ────────────────
self.addEventListener('notificationclick', (event) => {
  event.notification.close()

  const targetUrl = event.notification.data?.url ?? '/'

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      // If the app is already open, focus it
      for (const client of windowClients) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          return client.focus()
        }
      }
      // Otherwise open a new window
      return self.clients.openWindow(targetUrl)
    })
  )
})
