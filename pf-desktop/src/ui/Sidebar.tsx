import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { setSection } from '../app/AppProvider'
import { useAppStore } from '../app/appStore'
import { useAuth } from '../auth/AuthProvider'
import { isAdvancedAccount } from '../licensing/licenseGates'
import { SidebarIconView } from './icons'
import { buildSidebar } from './sidebarModel'
import { nextPersonName, normalizePeopleSettings } from '../domain/people'
import { isTauriRuntime, deletePersonTransactionsFromTauriFiles } from '../storage/tauriJsonStore'
import { deletePersonTransactionsFromLocalStorage } from '../storage/localJsonStore'
import { currency } from '../domain/finance'

export function Sidebar() {
  const { state, dispatch } = useAppStore()
  const auth = useAuth()
  const advanced = useMemo(() => isAdvancedAccount(auth.entitlements), [auth.entitlements])
  const groups = useMemo(() => buildSidebar(state, advanced), [advanced, state])
  const settings = useMemo(() => normalizePeopleSettings(state.settings), [state.settings])
  const [peopleModalOpen, setPeopleModalOpen] = useState(false)
  const [peopleModalMode, setPeopleModalMode] = useState<'add' | 'rename'>('add')
  const [peopleModalPersonId, setPeopleModalPersonId] = useState<string>('')
  const [peopleModalName, setPeopleModalName] = useState<string>('')
  const peopleNameInputRef = useRef<HTMLInputElement | null>(null)

  useEffect(() => {
    if (!peopleModalOpen) return
    window.setTimeout(() => peopleNameInputRef.current?.focus(), 0)
  }, [peopleModalOpen])

  const setActivePersonId = useCallback(
    (id: string) => {
      const target = settings.people.find((p) => p.id === id)
      const owed = Number((target as any)?.amountOwed ?? 0)
      dispatch({ type: 'settings/update', patch: { activePersonId: id } })
      dispatch({ type: 'ui/selectTransaction', id: null })
      if (Number.isFinite(owed) && owed < 0) {
        const abs = Math.abs(owed)
        const who = target?.name || 'This person'
        window.alert(`Reminder: ${who} still owes you ${currency(abs, settings.displayCurrencyCode)}.`)
      }
    },
    [dispatch, settings.displayCurrencyCode, settings.people]
  )

  const openAddPerson = useCallback(() => {
    setPeopleModalMode('add')
    setPeopleModalPersonId('')
    setPeopleModalName(nextPersonName(settings.people))
    setPeopleModalOpen(true)
  }, [settings.people])

  const openRenamePerson = useCallback(
    (id: string) => {
      const p = settings.people.find((x) => x.id === id)
      if (!p) return
      setPeopleModalMode('rename')
      setPeopleModalPersonId(id)
      setPeopleModalName(p.name)
      setPeopleModalOpen(true)
    },
    [settings.people]
  )

  const savePeopleModal = useCallback(() => {
    const clean = peopleModalName.trim()
    if (!clean) return
    if (peopleModalMode === 'add') {
      const id = crypto.randomUUID()
      dispatch({
        type: 'settings/update',
        patch: {
          people: [...settings.people, { id, name: clean, phone: null, email: null, address: null, notes: null, amountOwed: null }],
          activePersonId: id,
          peopleEnabled: true,
        },
      })
      dispatch({ type: 'ui/selectTransaction', id: null })
      setPeopleModalOpen(false)
      return
    }
    const id = peopleModalPersonId
    if (!id) return
    dispatch({
      type: 'settings/update',
      patch: { people: settings.people.map((x) => (x.id === id ? { ...x, name: clean } : x)) },
    })
    setPeopleModalOpen(false)
  }, [dispatch, peopleModalMode, peopleModalName, peopleModalPersonId, settings.people])

  const deletePerson = useCallback(async () => {
    if (peopleModalMode !== 'rename') return
    const id = peopleModalPersonId
    if (!id) return
    if (settings.people.length <= 1) return
    const p = settings.people.find((x) => x.id === id)
    const ok = window.confirm(`Delete person "${p?.name ?? 'Unknown'}"?\n\nThis will delete only that person's transactions.`)
    if (!ok) return

    if (isTauriRuntime()) {
      await deletePersonTransactionsFromTauriFiles(id)
    } else {
      deletePersonTransactionsFromLocalStorage(id)
    }

    const nextPeople = settings.people.filter((x) => x.id !== id)
    const nextCounts = { ...(settings.peopleTransactionCounts ?? {}) }
    delete nextCounts[id]
    const nextActive = settings.activePersonId === id ? nextPeople[0]!.id : settings.activePersonId
    dispatch({ type: 'settings/update', patch: { people: nextPeople, activePersonId: nextActive, peopleTransactionCounts: nextCounts } })
    dispatch({ type: 'ui/selectTransaction', id: null })
    setPeopleModalOpen(false)
  }, [dispatch, peopleModalMode, peopleModalPersonId, settings.activePersonId, settings.people, settings.peopleTransactionCounts])

  return (
    <aside className="sidebar" data-tauri-drag-region>
      <div className="sidebarDragGutter" data-tauri-drag-region />
      <div className="brand" data-tauri-drag-region>Kivana</div>
      <nav className="sbNav">
        {groups.map((g) => (
          <div key={g.title} className="sbGroup">
            <div className="sbGroupTitle" data-tauri-drag-region>{g.title}</div>
            {g.items.map((item) => {
              const active = state.ui.section === item.section
              return (
                <button
                  key={item.section}
                  type="button"
                  className={active ? 'sbItem active' : 'sbItem'}
                  onClick={() => dispatch(setSection(item.section))}
                >
                  <SidebarIconView icon={item.icon} dueSeverity={item.dueSeverity} />
                  <span className="sbText">
                    <span className="sbTitle">{item.title}</span>
                    {item.subtitle ? <span className="sbSubtitle">{item.subtitle}</span> : null}
                  </span>
                </button>
              )
            })}
          </div>
        ))}
        {advanced && settings.peopleEnabled ? (
          <div className="sbGroup">
            <div className="sbGroupTitle" data-tauri-drag-region>People</div>
            {settings.people.map((p) => {
              const active = settings.activePersonId === p.id
              const count = Number(settings.peopleTransactionCounts?.[p.id] ?? (active ? state.transactions.length : 0))
              return (
                <div key={p.id} style={{ display: 'flex', gap: 6 }}>
                  <button
                    type="button"
                    className={active ? 'sbItem active' : 'sbItem'}
                    style={{ flex: 1 }}
                    onClick={() => setActivePersonId(p.id)}
                  >
                    <SidebarIconView icon="transactions" />
                    <span className="sbText">
                      <span className="sbTitle">{p.name}</span>
                      <span className="sbSubtitle">{count === 0 ? 'No transactions' : `${count} transactions`}</span>
                    </span>
                  </button>
                  <button type="button" className="sbItem" style={{ width: 60, justifyContent: 'center' }} onClick={() => openRenamePerson(p.id)}>
                    Edit
                  </button>
                </div>
              )
            })}
            <button type="button" className="sbItem" onClick={openAddPerson}>
              <SidebarIconView icon="transactions" />
              <span className="sbText">
                <span className="sbTitle">Add person</span>
                <span className="sbSubtitle">Separate transactions</span>
              </span>
            </button>
          </div>
        ) : null}
      </nav>
      <div className="sidebarDragSpacer" data-tauri-drag-region />
      {peopleModalOpen ? (
        <div className="modalBackdrop">
          <div className="modal">
            <div className="modalTitle">{peopleModalMode === 'add' ? 'Add person' : 'Rename person'}</div>
            <div className="field" style={{ marginTop: 12 }}>
              <div className="fieldLabel">Name</div>
              <input
                ref={peopleNameInputRef}
                value={peopleModalName}
                onChange={(e) => setPeopleModalName(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') savePeopleModal()
                  if (e.key === 'Escape') setPeopleModalOpen(false)
                }}
              />
            </div>
            <div className="modalActions">
              <button type="button" onClick={() => setPeopleModalOpen(false)}>
                Cancel
              </button>
              {peopleModalMode === 'rename' && settings.people.length > 1 ? (
                <button type="button" onClick={() => void deletePerson()}>
                  Delete
                </button>
              ) : null}
              <button type="button" onClick={savePeopleModal}>
                Save
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </aside>
  )
}
