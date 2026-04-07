/**
 * Type-safe wrapper around the Electron preload bridge.
 */
export const electron = (window as any).electronAPI as {
  oauthLogin: (authUrl: string) => Promise<string | null>
  getVersion: () => Promise<string>
  setTrayBadge: (count: number) => void
  showNotification: (title: string, body: string) => void
} | undefined
