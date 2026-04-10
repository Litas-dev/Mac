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

function App() {
  const store = useAppStore()
  const { state, dispatch } = store
  const auth = useAuth()
  const stateRef = useRef(store.state)
  stateRef.current = store.state

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
            <CommandBar />
            <div className="toolbarRight">
              <div className="toolbarTitle">{titleForSection(state.ui.section)}</div>
              <input className="toolbarSearch" placeholder="Search" />
              {auth.ready ? (
                auth.session ? (
                  <button type="button" className="accountButton" onClick={() => auth.setOpenLogin(true)}>
                    <span className="accountEmail">{auth.session.userEmail}</span>
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
      return 'Transactions'
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
