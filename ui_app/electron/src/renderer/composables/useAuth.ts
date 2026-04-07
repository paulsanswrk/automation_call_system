import { ref, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { electron } from '@/lib/electron'
import type { User, Session } from '@supabase/supabase-js'

const user = ref<User | null>(null)
const session = ref<Session | null>(null)
const loading = ref(true)

export function useAuth() {
  onMounted(() => {
    supabase.auth.getSession().then(({ data }) => {
      session.value = data.session
      user.value = data.session?.user ?? null
      loading.value = false
    })

    supabase.auth.onAuthStateChange((_event, newSession) => {
      session.value = newSession
      user.value = newSession?.user ?? null
      loading.value = false
    })
  })

  /**
   * Sign in with Google via Electron's in-app BrowserWindow.
   * Falls back to regular OAuth redirect if not in Electron.
   */
  async function signInWithGoogle() {
    if (electron) {
      // Build the OAuth URL manually
      const { data, error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo: import.meta.env.VITE_SUPABASE_URL,
          skipBrowserRedirect: true,
        },
      })
      if (error) throw error
      if (!data.url) throw new Error('No OAuth URL returned')

      // Open in Electron BrowserWindow
      const redirectUrl = await electron.oauthLogin(data.url)
      if (!redirectUrl) throw new Error('Login cancelled')

      // Extract tokens from URL fragment
      const hashParams = new URLSearchParams(
        redirectUrl.includes('#') ? redirectUrl.split('#')[1] : redirectUrl.split('?')[1]
      )
      const accessToken = hashParams.get('access_token')
      const refreshToken = hashParams.get('refresh_token')

      if (accessToken && refreshToken) {
        const { error: setError } = await supabase.auth.setSession({
          access_token: accessToken,
          refresh_token: refreshToken,
        })
        if (setError) throw setError
      } else {
        throw new Error('Could not extract tokens from redirect')
      }
    } else {
      // Fallback for browser dev mode
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: window.location.origin },
      })
      if (error) throw error
    }
  }

  async function signOut() {
    const { error } = await supabase.auth.signOut()
    if (error) throw error
  }

  return {
    user,
    session,
    loading,
    signInWithGoogle,
    signOut,
  }
}
