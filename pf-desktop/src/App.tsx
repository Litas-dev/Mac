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

function App() {
  const store = useAppStore()
  const { state, dispatch } = store
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
      <Sidebar />

      <main className="main">
        <header className="topbar">
          <div className="dragRegion" data-tauri-drag-region />
          <div className="appToolbar">
            <button type="button" className="toolbarPlus" onClick={() => dispatch({ type: 'ui/setSection', section: 'ai' })}>
              +
            </button>
            <CommandBar />
            <div className="toolbarRight">
              <div className="toolbarTitle">{titleForSection(state.ui.section)}</div>
              <input className="toolbarSearch" placeholder="Search" />
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
    case 'ai':
      return 'AI'
    default:
      return 'Kivana'
  }
}
