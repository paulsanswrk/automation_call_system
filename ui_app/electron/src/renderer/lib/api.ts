import { supabase } from './supabase'

const API_BASE = import.meta.env.VITE_API_BASE_URL ?? ''

/**
 * Authenticated fetch wrapper.
 * Reads the current Supabase session and attaches the JWT
 * as a Bearer token in the Authorization header.
 */
export async function apiFetch(path: string, init?: RequestInit): Promise<Response> {
  const { data: { session } } = await supabase.auth.getSession()

  return fetch(`${API_BASE}${path}`, {
    ...init,
    headers: {
      ...init?.headers,
      Authorization: `Bearer ${session?.access_token ?? ''}`,
    },
  })
}
