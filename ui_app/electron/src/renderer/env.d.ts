/// <reference types="vite/client" />

declare const __APP_VERSION__: string

interface ElectronAPI {
  oauthLogin: (authUrl: string) => Promise<string | null>
  getVersion: () => Promise<string>
  setTrayBadge: (count: number) => void
  showNotification: (title: string, body: string) => void
}

interface Window {
  electronAPI: ElectronAPI
}
