import { contextBridge, ipcRenderer } from 'electron'

contextBridge.exposeInMainWorld('electronAPI', {
  /** Opens an OAuth window and returns the redirect URL containing tokens */
  oauthLogin: (authUrl: string): Promise<string | null> =>
    ipcRenderer.invoke('auth:oauth-login', authUrl),

  /** Returns the app version from package.json */
  getVersion: (): Promise<string> =>
    ipcRenderer.invoke('app:get-version'),

  /** Updates the tray icon badge count */
  setTrayBadge: (count: number): void =>
    ipcRenderer.send('tray:set-badge', count),

  /** Shows a native OS notification */
  showNotification: (title: string, body: string): void =>
    ipcRenderer.send('notifications:show-native', title, body),
})
