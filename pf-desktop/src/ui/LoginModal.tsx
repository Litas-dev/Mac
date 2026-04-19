import { useEffect, useMemo, useState } from 'react'
import { useAuth } from '../auth/AuthProvider'
import { loadLastLoginEmail, saveLastLoginEmail } from '../storage/userPrefs'

export function LoginModal() {
  const auth = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [status, setStatus] = useState('')

  const shouldShow = useMemo(() => auth.openLogin && auth.ready, [auth.openLogin, auth.ready])

  useEffect(() => {
    if (email) return
    const remembered = loadLastLoginEmail()
    if (remembered) setEmail(remembered)
  }, [email])

  const kivanaPlan = useMemo(() => {
    const p = auth.entitlements?.products?.find((x) => x.productCode === 'kivana') ?? auth.entitlements?.products?.[0]
    if (!p) return null
    return `${p.productCode} / ${p.planName}`
  }, [auth.entitlements])

  async function signInClick() {
    setStatus('')
    try {
      await auth.signIn(email, password)
      saveLastLoginEmail(email)
      setStatus('')
    } catch (e: any) {
      setStatus(`Sign in failed: ${String(e?.message ?? e)}`)
    }
  }

  async function signUpClick() {
    setStatus('')
    try {
      await auth.signUp(email, password)
      saveLastLoginEmail(email)
      setStatus('')
    } catch (e: any) {
      setStatus(`Sign up failed: ${String(e?.message ?? e)}`)
    }
  }

  async function signOutClick() {
    setStatus('')
    try {
      await auth.signOut()
      setStatus('')
    } catch (e: any) {
      setStatus(`Sign out failed: ${String(e?.message ?? e)}`)
    }
  }

  async function refreshEntitlementsClick() {
    setStatus('')
    try {
      await auth.refreshEntitlements()
      setStatus('')
    } catch (e: any) {
      setStatus(`Refresh failed: ${String(e?.message ?? e)}`)
    }
  }

  if (!shouldShow) return null

  return (
    <div className="modalBackdrop">
      <div className="modal">
        <div className="modalTitle">Account</div>
        {auth.session ? (
          <>
            <div className="note">Signed in: {auth.session.userEmail}</div>
            {kivanaPlan ? <div className="note">Plan: {kivanaPlan}</div> : null}
            <div className="modalActions">
              <button type="button" onClick={() => auth.setOpenLogin(false)}>
                Close
              </button>
              <button type="button" onClick={() => void refreshEntitlementsClick()}>
                Refresh
              </button>
              <button type="button" onClick={() => void signOutClick()}>
                Sign out
              </button>
            </div>
            {status ? <div className="note">{status}</div> : null}
          </>
        ) : (
          <>
            <div className="note">Create an account or sign in. Your plan will show here.</div>
            <div className="field" style={{ marginTop: 12 }}>
              <div className="fieldLabel">Email</div>
              <input value={email} onChange={(e) => setEmail(e.target.value)} />
            </div>
            <div className="field" style={{ marginTop: 12 }}>
              <div className="fieldLabel">Password</div>
              <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
            </div>
            <div className="modalActions">
              <button type="button" onClick={() => auth.setOpenLogin(false)}>
                Cancel
              </button>
              <button type="button" onClick={() => void signUpClick()}>
                Create account
              </button>
              <button type="button" onClick={() => void signInClick()}>
                Sign in
              </button>
            </div>
            {status ? <div className="note">{status}</div> : null}
          </>
        )}
      </div>
    </div>
  )
}
