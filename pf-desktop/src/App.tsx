import './App.css'
import { useEffect, useRef, useState } from 'react'
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
import type { Bill, Income } from './domain/models'

function App() {
  const store = useAppStore()
  const { state, dispatch } = store
  const auth = useAuth()
  const advanced = isAdvancedAccount(auth.entitlements)
  const [sidebarExpanded, setSidebarExpanded] = useState(false)
  const stateRef = useRef(store.state)
  stateRef.current = store.state
  const accountLabel = auth.session ? displayNameForEmail(auth.session.userEmail) : ''
  const peopleSettings = normalizePeopleSettings(state.settings as any)
  const activePerson =
    advanced && peopleSettings.peopleEnabled ? peopleSettings.people.find((p) => p.id === peopleSettings.activePersonId) ?? null : null
  const sectionTitle = titleForSection(state.ui.section)
  const showCommandBar = state.ui.section === 'bills'
  const [quickAddOpen, setQuickAddOpen] = useState(false)
  const quickAddButtonRef = useRef<HTMLButtonElement | null>(null)
  const [quickAddPos, setQuickAddPos] = useState<{ left: number; top: number; width: number } | null>(null)

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

  const enableMenuAnimations = state.settings.enableMenuAnimations
  const effectiveSidebarExpanded = enableMenuAnimations ? sidebarExpanded : true
  const quickAddWidth = 220

  function openQuickAdd() {
    const el = quickAddButtonRef.current
    if (!el) return
    const r = el.getBoundingClientRect()
    const margin = 10
    const left = Math.max(margin, Math.min(r.right - quickAddWidth, window.innerWidth - quickAddWidth - margin))
    const top = r.bottom + 8
    setQuickAddPos({ left, top, width: quickAddWidth })
    setQuickAddOpen(true)
  }

  function closeQuickAdd() {
    setQuickAddOpen(false)
    setQuickAddPos(null)
  }

  function toggleQuickAdd() {
    if (quickAddOpen) {
      closeQuickAdd()
      return
    }
    openQuickAdd()
  }

  function createBillFromTopBar() {
    const now = new Date()
    const b: Bill = {
      id: crypto.randomUUID(),
      name: 'New Bill',
      amount: { currencyCode: state.settings.displayCurrencyCode, value: 0 },
      category: 'other',
      customCategoryName: null,
      recurrence: 'monthly',
      nextDueDate: now,
      notes: null,
      payments: [],
      paidAutomatically: false,
      hiddenUntilEdited: false,
      snoozeUntil: null,
      snoozeCount: 0,
      attachments: [],
    }
    dispatch({ type: 'bills/add', bill: b })
    dispatch({ type: 'ui/setSection', section: 'bills' })
    dispatch({ type: 'ui/selectBill', id: b.id })
    closeQuickAdd()
  }

  function createIncomeFromTopBar() {
    const now = new Date()
    const inc: Income = {
      id: crypto.randomUUID(),
      name: 'New Income',
      amount: { currencyCode: state.settings.displayCurrencyCode, value: 0 },
      source: 'salary',
      customSourceName: null,
      recurrence: 'monthly',
      nextPayDate: now,
      notes: null,
      receipts: [],
    }
    dispatch({ type: 'incomes/add', income: inc })
    dispatch({ type: 'ui/setSection', section: 'income' })
    dispatch({ type: 'ui/selectIncome', id: inc.id })
    closeQuickAdd()
  }

  return (
    <div
      className={
        (effectiveSidebarExpanded ? 'shell shellSidebarExpanded' : 'shell shellSidebarCollapsed') +
        (enableMenuAnimations ? '' : ' noMenuAnimations')
      }
    >
      <OnboardingModal />
      <LoginModal />
      <UpdateWatcher />
      <Sidebar onHoverChange={enableMenuAnimations ? setSidebarExpanded : undefined} />

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
              <button type="button" className="toolbarPlus" onClick={toggleQuickAdd} ref={quickAddButtonRef}>
                +
              </button>
            </div>
          </div>
        </header>
        {quickAddOpen && quickAddPos ? (
          <>
            <div className="popoverOverlay" onMouseDown={closeQuickAdd} />
            <div className="popoverPanel" style={{ left: quickAddPos.left, top: quickAddPos.top, right: 'auto', width: quickAddPos.width }}>
              <div className="groupTitle" style={{ marginBottom: 8 }}>
                Create
              </div>
              <div className="rowActions" style={{ flexDirection: 'column', alignItems: 'stretch' }}>
                <button type="button" onClick={createBillFromTopBar}>
                  New Bill
                </button>
                <button type="button" onClick={createIncomeFromTopBar}>
                  New Income
                </button>
              </div>
            </div>
          </>
        ) : null}
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
