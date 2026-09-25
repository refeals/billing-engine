import { ref } from 'vue'
import { defineStore } from 'pinia'

import { ApiError } from '@/api/client'
import { fetchSession, signIn as requestSignIn, signOut as requestSignOut, type SessionUser } from '@/api/session'

export const useAuthStore = defineStore('auth', () => {
  const user = ref<SessionUser | null>(null)
  const status = ref<'unknown' | 'signed_in' | 'signed_out'>('unknown')
  let loading: Promise<void> | null = null

  // Asks the API once per page load whether the cookie still holds a session. Only a 401
  // means "signed out"; a network error is rethrown so the app doesn't pretend to know.
  function load(): Promise<void> {
    if (status.value !== 'unknown') return Promise.resolve()

    loading ??= fetchSession()
      .then((result) => setUser(result.user))
      .catch((error: unknown) => {
        if (error instanceof ApiError && error.status === 401) return reset()
        throw error
      })
      .finally(() => {
        loading = null
      })
    return loading
  }

  async function signIn(email: string, password: string) {
    const result = await requestSignIn(email, password)
    setUser(result.user)
  }

  // Signs out locally even if the request fails: the user asked to leave.
  async function signOut() {
    try {
      await requestSignOut()
    } catch {
      // The session may already be gone (expired); nothing to undo.
    } finally {
      reset()
    }
  }

  function setUser(value: SessionUser) {
    user.value = value
    status.value = 'signed_in'
  }

  function reset() {
    user.value = null
    status.value = 'signed_out'
  }

  return { user, status, load, signIn, signOut, reset }
})
