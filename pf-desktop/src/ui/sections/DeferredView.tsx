import { useMemo } from 'react'
import { useAppStore } from '../../app/appStore'
import { setSection } from '../../app/AppProvider'
import { billIsSnoozedActive } from '../../domain/models'
import { toDateInputValue } from '../date'

export function DeferredView() {
  const { state, dispatch } = useAppStore()
  const now = new Date()

  const deferred = useMemo(() => {
    return state.bills
      .filter((b) => billIsSnoozedActive(b, now))
      .sort((a, b) => (a.snoozeUntil?.getTime() ?? 0) - (b.snoozeUntil?.getTime() ?? 0))
  }, [now, state.bills])

  function openBill(id: string) {
    dispatch({ type: 'ui/selectBill', id })
    dispatch(setSection('bills'))
  }

  function clear(id: string) {
    dispatch({ type: 'bills/clearSnooze', id })
  }

  return (
    <>
      {deferred.length === 0 ? (
        <div className="note">No bills are snoozed.</div>
      ) : (
        <div className="list" style={{ marginTop: 12 }}>
          {deferred.map((b) => (
            <div
              key={b.id}
              className="note"
              style={{
                display: 'grid',
                gridTemplateColumns: '1fr auto auto',
                gap: 8,
                padding: '10px 12px',
                borderBottom: '1px solid rgba(255,255,255,0.06)',
              }}
            >
              <div style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {b.name} • Snoozed until {b.snoozeUntil ? toDateInputValue(b.snoozeUntil) : '—'}
              </div>
              <button type="button" onClick={() => clear(b.id)} style={{ padding: '2px 8px' }}>
                Clear
              </button>
              <button type="button" onClick={() => openBill(b.id)} style={{ padding: '2px 8px' }}>
                Open
              </button>
            </div>
          ))}
        </div>
      )}
    </>
  )
}
