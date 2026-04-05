import { useMemo } from 'react'
import { useAppStore } from '../../app/appStore'
import { setSection } from '../../app/AppProvider'
import { currency } from '../../domain/finance'
import { toDateInputValue } from '../date'

type Activity =
  | { id: string; kind: 'bill'; name: string; amount: number; currencyCode: string; date: Date; billId: string }
  | { id: string; kind: 'income'; name: string; amount: number; currencyCode: string; date: Date; incomeId: string }

export function PaidRecentlyView() {
  const { state, dispatch } = useAppStore()

  const activities = useMemo(() => {
    const now = new Date()
    const past = new Date(now)
    past.setDate(past.getDate() - 30)

    const items: Activity[] = []
    for (const bill of state.bills) {
      for (const p of bill.payments ?? []) {
        if (p.date >= past) {
          items.push({
            id: p.id,
            kind: 'bill',
            name: bill.name,
            amount: p.amount.value,
            currencyCode: p.amount.currencyCode,
            date: p.date,
            billId: bill.id,
          })
        }
      }
    }
    for (const inc of state.incomes) {
      for (const r of inc.receipts ?? []) {
        if (r.date >= past) {
          items.push({
            id: r.id,
            kind: 'income',
            name: inc.name,
            amount: r.amount.value,
            currencyCode: r.amount.currencyCode,
            date: r.date,
            incomeId: inc.id,
          })
        }
      }
    }
    return items.sort((a, b) => b.date.getTime() - a.date.getTime())
  }, [state.bills, state.incomes])

  function open(a: Activity) {
    if (a.kind === 'bill') {
      dispatch({ type: 'ui/selectBill', id: a.billId })
      dispatch(setSection('bills'))
      return
    }
    dispatch({ type: 'ui/selectIncome', id: a.incomeId })
    dispatch(setSection('income'))
  }

  return (
    <>
      {activities.length === 0 ? (
        <div className="note">No recent activity.</div>
      ) : (
        <div className="list" style={{ marginTop: 12 }}>
          {activities.map((a) => (
            <button
              key={`${a.kind}:${a.id}`}
              type="button"
              className="listItem"
              onClick={() => open(a)}
              style={{ display: 'grid', gridTemplateColumns: '1fr auto auto', alignItems: 'center' }}
            >
              <div className="listTitle" style={{ margin: 0 }}>
                {a.kind === 'bill' ? 'Bill' : 'Income'} • {a.name}
              </div>
              <div className="listMeta">{toDateInputValue(a.date)}</div>
              <div className="listMeta">{currency(a.amount, a.currencyCode)}</div>
            </button>
          ))}
        </div>
      )}
    </>
  )
}
