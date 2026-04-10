import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { getMe, refreshToken as refreshTokenCall, signIn as signInCall, signOut as signOutCall, signUp as signUpCall } from './authApi'
import { loadAuthSession, saveAuthSession, type AuthSession } from './authStore'
import { getEntitlements, type EntitlementsResponse } from '../licensing/entitlementsApi'
import { loadEntitlements, saveEntitlements } from '../licensing/entitlementsStore'

export interface AuthContextValue {
  ready: boolean
  session: AuthSession | null
  entitlements: EntitlementsResponse | null
  openLogin: boolean
  setOpenLogin: (v: boolean) => void
  signUp: (email: string, password: string) => Promise<void>
  signIn: (email: string, password: string) => Promise<void>
  signOut: () => Promise<void>
  refreshEntitlements: () => Promise<void>
  getValidSession: () => Promise<AuthSession | null>
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function useAuth(): AuthContextValue {
  const v = useContext(AuthContext)
  if (!v) throw new Error('AuthContext is not available')
  return v
}

function normalizeBaseURL(baseURL: string): string {
  const trimmed = baseURL.trim()
  return trimmed.replace(/\/+$/, '')
}

const HARDCODED_BACKEND_URL = normalizeBaseURL(import.meta.env.VITE_BACKEND_URL || '')

export function AuthProvider(props: { children: React.ReactNode }) {
  const [ready, setReady] = useState(false)
  const [session, setSession] = useState<AuthSession | null>(null)
  const [entitlements, setEntitlements] = useState<EntitlementsResponse | null>(null)
  const [openLogin, setOpenLogin] = useState(false)

  const effectiveBaseURL = HARDCODED_BACKEND_URL

  const clearAll = useCallback(async () => {
    setSession(null)
    setEntitlements(null)
    await saveAuthSession(null)
    await saveEntitlements(null)
  }, [])

  const ensureValidSession = useCallback(
    async (s: AuthSession): Promise<AuthSession | null> => {
      const base = normalizeBaseURL(s.backendBaseURL || effectiveBaseURL)
      try {
        await getMe(base, s.accessToken)
        return s
      } catch (e: any) {
        const msg = String(e?.message ?? '')
        if (!(msg === 'invalid_token' || msg === 'missing_token' || msg.includes('401') || msg.includes('403'))) {
          // Network error or 5xx error, assume session is still valid for offline use
          return s
        }
      }

      try {
        const refreshed = await refreshTokenCall(base, s.refreshToken)
        const next: AuthSession = {
          backendBaseURL: base,
          accessToken: refreshed.accessToken,
          refreshToken: refreshed.refreshToken,
          userId: refreshed.user.id,
          userEmail: refreshed.user.email,
          updatedAt: new Date().toISOString(),
        }
        setSession(next)
        await saveAuthSession(next)
        return next
      } catch (e: any) {
        const msg = String(e?.message ?? '')
        if (!(msg === 'invalid_refresh_token' || msg.includes('401') || msg.includes('403') || msg.includes('400'))) {
          // Network error or 5xx error, assume session is still valid
          return s
        }
        return null
      }
    },
    [effectiveBaseURL],
  )

  const getValidSession = useCallback(async (): Promise<AuthSession | null> => {
    if (!session) return null
    const valid = await ensureValidSession(session)
    if (!valid) {
      await clearAll()
    }
    return valid
  }, [session, ensureValidSession, clearAll])

  const refreshEntitlements = useCallback(async () => {
    const s = await getValidSession()
    if (!s?.accessToken) return
    const base = normalizeBaseURL(s.backendBaseURL || effectiveBaseURL)
    const e = await getEntitlements(base, s.accessToken)
    setEntitlements(e)
    await saveEntitlements(e)
  }, [effectiveBaseURL, getValidSession])

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const [savedSession, savedEntitlements] = await Promise.all([loadAuthSession(), loadEntitlements()])
      if (cancelled) return
      setEntitlements(savedEntitlements)
      if (!savedSession) {
        setSession(null)
        setReady(true)
        return
      }

      const valid = await ensureValidSession(savedSession)
      if (cancelled) return
      if (!valid) {
        await clearAll()
        setReady(true)
        return
      }

      setSession(valid)
      await saveAuthSession(valid)
      try {
        const base = normalizeBaseURL(valid.backendBaseURL || effectiveBaseURL)
        const e = await getEntitlements(base, valid.accessToken)
        if (!cancelled) {
          setEntitlements(e)
          await saveEntitlements(e)
        }
      } catch {
      }
      if (!cancelled) {
        setReady(true)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [clearAll, effectiveBaseURL, ensureValidSession])

  const signUp = useCallback(
    async (email: string, password: string) => {
      const base = normalizeBaseURL(effectiveBaseURL)
      const r = await signUpCall(base, email, password)
      const next: AuthSession = {
        backendBaseURL: base,
        accessToken: r.accessToken,
        refreshToken: r.refreshToken,
        userId: r.user.id,
        userEmail: r.user.email,
        updatedAt: new Date().toISOString(),
      }
      setSession(next)
      await saveAuthSession(next)
      setOpenLogin(false)
      try {
        const e = await getEntitlements(base, next.accessToken)
        setEntitlements(e)
        await saveEntitlements(e)
      } catch {
      }
    },
    [effectiveBaseURL],
  )

  const signIn = useCallback(
    async (email: string, password: string) => {
      const base = normalizeBaseURL(effectiveBaseURL)
      const r = await signInCall(base, email, password)
      const next: AuthSession = {
        backendBaseURL: base,
        accessToken: r.accessToken,
        refreshToken: r.refreshToken,
        userId: r.user.id,
        userEmail: r.user.email,
        updatedAt: new Date().toISOString(),
      }
      setSession(next)
      await saveAuthSession(next)
      setOpenLogin(false)
      try {
        const e = await getEntitlements(base, next.accessToken)
        setEntitlements(e)
        await saveEntitlements(e)
      } catch {
      }
    },
    [effectiveBaseURL],
  )

  const signOut = useCallback(async () => {
    const s = session
    await clearAll()
    if (!s?.refreshToken) return
    const base = normalizeBaseURL(s.backendBaseURL || effectiveBaseURL)
    try {
      await signOutCall(base, s.refreshToken)
    } catch {
    }
  }, [clearAll, effectiveBaseURL, session])

  const value = useMemo<AuthContextValue>(
    () => ({
      ready,
      session,
      entitlements,
      openLogin,
      setOpenLogin,
      signUp,
      signIn,
      signOut,
      refreshEntitlements,
      getValidSession,
    }),
    [entitlements, openLogin, ready, refreshEntitlements, session, signIn, signOut, signUp, getValidSession],
  )

  return <AuthContext.Provider value={value}>{props.children}</AuthContext.Provider>
}
