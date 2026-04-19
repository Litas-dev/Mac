import './App.css'
import { useEffect, useRef } from 'react'
import { useAppStore } from './app/appStore'
import { SectionRouter } from './ui/SectionRouter'
import { OnboardingModal } from './ui/OnboardingModal'
import { isTauriRuntime } from './storage/tauriJsonStore'
import { registerMenuEvents } from './ui/menuEvents'
import { registerTouchBarEvents } from './ui/touchbarEvents'
import { Sidebar } from './ui/Sidebar'
import { CommandBar } from './ui/CommandBar'
import { UpdateWatcher } from './ui/UpdateWatcher'
import { useAuth } from './auth/AuthProvider'
import { LoginModal } from './ui/LoginModal'
import { normalizePeopleSettings } from './domain/people'
import { isAdvancedAccount } from './licensing/licenseGates'

function App() {
  const store = useAppStore()
  const { state, dispatch } = store
  const auth = useAuth()
  const advanced = isAdvancedAccount(auth.entitlements)
  const stateRef = useRef(store.state)
  stateRef.current = store.state
  const accountLabel = auth.session ? displayNameForEmail(auth.session.userEmail) : ''
  const peopleSettings = normalizePeopleSettings(state.settings as any)
  const activePerson =
    advanced && peopleSettings.peopleEnabled ? peopleSettings.people.find((p) => p.id === peopleSettings.activePersonId) ?? null : null
  const sectionTitle = titleForSection(state.ui.section)
  const showCommandBar = state.ui.section === 'bills'

  useEffect(() => {
    if (!isTauriRuntime()) return
    let cleanup: (() => void) | null = null
    const cleanupTouch = registerTouchBarEvents(dispatch, () => stateRef.current)
    void registerMenuEvents(() => stateRef.current, dispatch).then((c) => {
      cleanup = c
    })
    return () => {
      cleanup?.()
      cleanupTouch()
    }
  }, [dispatch])

  return (
    <div className="shell">
      <OnboardingModal />
      <LoginModal />
      <UpdateWatcher />
      <Sidebar />

      <main className="main">
        <header className="topbar">
          <div className="windowDragStrip" data-tauri-drag-region>
            <div className="windowDragHandle" data-tauri-drag-region />
          </div>
          <div className="appToolbar" data-tauri-drag-region>
            <div className="toolbarLeft">
              {auth.ready ? (
                auth.session ? (
                  <button type="button" className="accountButton" onClick={() => auth.setOpenLogin(true)}>
                    <span className="accountEmail">{accountLabel}</span>
                    <span className="planBadge">
                      {(auth.entitlements?.products?.find((p) => p.productCode === 'kivana')?.planName ||
                        auth.entitlements?.products?.[0]?.planName ||
                        'Basic') as string}
                    </span>
                  </button>
                ) : (
                  <button type="button" className="accountButton" onClick={() => auth.setOpenLogin(true)}>
                    Account
                  </button>
                )
              ) : null}
            </div>
            {showCommandBar ? <CommandBar /> : <div />}
            <div className="toolbarRight">
              {sectionTitle ? <div className="toolbarTitle">{sectionTitle}</div> : null}
              {activePerson ? <span className="personBadge">{activePerson.name}</span> : null}
            </div>
          </div>
        </header>
        <section className="panel content">
          <SectionRouter />
        </section>
      </main>
    </div>
  )
}

export default App

function titleForSection(section: string): string {
  switch (section) {
    case 'dashboard':
      return 'Overview'
    case 'calendar':
      return 'Calendar'
    case 'bills':
      return 'Bills'
    case 'income':
      return 'Income'
    case 'dueSoon':
      return 'Due Soon'
    case 'deferred':
      return 'Deferred'
    case 'paidRecently':
      return 'Paid Recently'
    case 'accounts':
      return 'Accounts'
    case 'transactions':
      return ''
    case 'invoices':
      return 'Files'
    case 'goals':
      return 'Goals'
    case 'debts':
      return 'Debts'
    case 'reports':
      return 'Reports'
    case 'settings':
      return 'Settings'
    default:
      return 'Kivana'
  }
}

function displayNameForEmail(email: string): string {
  const trimmed = String(email || '').trim()
  const at = trimmed.indexOf('@')
  if (at <= 0) return trimmed
  return trimmed.slice(0, at)
}
