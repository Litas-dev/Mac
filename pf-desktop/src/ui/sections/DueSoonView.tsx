import { useMemo } from 'react'
import { useAppStore } from '../../app/appStore'
import { setSection } from '../../app/AppProvider'
import { billIsPaidFor, billIsSnoozedActive } from '../../domain/models'
import { currency } from '../../domain/finance'
import { toDateInputValue } from '../date'

export function DueSoonView() {
  const { state, dispatch } = useAppStore()

  const dueSoon = useMemo(() => {
    const now = new Date()
    const start = new Date(now)
    start.setHours(0, 0, 0, 0)
    const cutoff = new Date(start)
    cutoff.setDate(cutoff.getDate() + 7)
    return state.bills
      .filter((b) => {
        if (b.hiddenUntilEdited) return false
        if (billIsSnoozedActive(b, now)) return false
        if (billIsPaidFor(b, b.nextDueDate)) return false
        const d = new Date(b.nextDueDate)
        d.setHours(0, 0, 0, 0)
        return d.getTime() >= start.getTime() && d.getTime() <= cutoff.getTime()
      })
      .sort((a, b) => a.nextDueDate.getTime() - b.nextDueDate.getTime())
  }, [state.bills])

  function openBill(id: string) {
    dispatch({ type: 'ui/selectBill', id })
    dispatch(setSection('bills'))
  }

  function markPaid(id: string) {
    const bill = state.bills.find((b) => b.id === id)
    if (!bill) return
    dispatch({ type: 'bills/logPayment', id, date: bill.nextDueDate })
  }

  function snooze7(id: string) {
    const until = new Date()
    until.setHours(0, 0, 0, 0)
    until.setDate(until.getDate() + 7)
    dispatch({ type: 'bills/setSnooze', id, until })
  }

  return (
    <>
      {dueSoon.length === 0 ? (
        <div className="note">All paid.</div>
      ) : (
        <div className="list" style={{ marginTop: 12 }}>
          {dueSoon.map((b) => (
            <div key={b.id} className="note" style={{ display: 'grid', gridTemplateColumns: '1fr auto auto auto', gap: 8, padding: '10px 12px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
              <div style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {b.name} • {toDateInputValue(b.nextDueDate)}
              </div>
              <div>{currency(b.amount.value, b.amount.currencyCode)}</div>
              <button type="button" onClick={() => markPaid(b.id)} style={{ padding: '2px 8px' }}>
                Paid
              </button>
              <button type="button" onClick={() => snooze7(b.id)} style={{ padding: '2px 8px' }}>
                Snooze
              </button>
              <button type="button" onClick={() => openBill(b.id)} style={{ padding: '2px 8px', gridColumn: '1 / -1' }}>
                Open
              </button>
            </div>
          ))}
        </div>
      )}
    </>
  )
}
