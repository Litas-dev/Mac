import { useMemo, useState } from 'react'
import { useAppStore } from '../../app/appStore'
import { billIsPaidFor, billIsSnoozedActive } from '../../domain/models'

type DayItem = { kind: 'bill' | 'income'; title: string }

export function CalendarView() {
  const { state } = useAppStore()
  const [cursor, setCursor] = useState(() => startOfMonth(new Date()))

  const monthLabel = useMemo(() => cursor.toLocaleString(undefined, { month: 'long', year: 'numeric' }), [cursor])

  const days = useMemo(() => {
    const start = startOfWeek(startOfMonth(cursor))
    const end = endOfWeek(endOfMonth(cursor))
    const out: Date[] = []
    let d = new Date(start)
    while (d.getTime() <= end.getTime()) {
      out.push(new Date(d))
      d.setDate(d.getDate() + 1)
    }
    return out
  }, [cursor])

  const itemsByDay = useMemo(() => {
    const now = new Date()
    const map = new Map<number, DayItem[]>()
    for (const b of state.bills) {
      if (b.hiddenUntilEdited) continue
      if (billIsSnoozedActive(b, now)) continue
      if (billIsPaidFor(b, b.nextDueDate)) continue
      const key = startOfDay(b.nextDueDate).getTime()
      const arr = map.get(key) ?? []
      arr.push({ kind: 'bill', title: b.name })
      map.set(key, arr)
    }
    for (const inc of state.incomes) {
      const key = startOfDay(inc.nextPayDate).getTime()
      const arr = map.get(key) ?? []
      arr.push({ kind: 'income', title: inc.name })
      map.set(key, arr)
    }
    return map
  }, [state.bills, state.incomes])

  return (
    <div className="calendar">
      <div className="calendarTop">
        <div className="calendarTitle">{monthLabel}</div>
        <div className="rowActions">
          <button type="button" onClick={() => setCursor(addMonths(cursor, -1))}>
            Prev
          </button>
          <button type="button" onClick={() => setCursor(startOfMonth(new Date()))}>
            Today
          </button>
          <button type="button" onClick={() => setCursor(addMonths(cursor, 1))}>
            Next
          </button>
        </div>
      </div>

      <div className="calendarGrid">
        {['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) => (
          <div key={d} className="calendarDow">
            {d}
          </div>
        ))}
        {days.map((d) => {
          const inMonth = d.getMonth() === cursor.getMonth()
          const key = startOfDay(d).getTime()
          const items = itemsByDay.get(key) ?? []
          return (
            <div key={key} className={`calendarDay ${inMonth ? '' : 'outside'}`}>
              <div className="calendarDayNum">{d.getDate()}</div>
              {items.slice(0, 3).map((it, idx) => (
                <div key={idx} className={`calendarPill ${it.kind}`}>
                  {it.title}
                </div>
              ))}
              {items.length > 3 ? <div className="calendarMore">+{items.length - 3}</div> : null}
            </div>
          )
        })}
      </div>
    </div>
  )
}

function startOfDay(d: Date): Date {
  const x = new Date(d)
  x.setHours(0, 0, 0, 0)
  return x
}

function startOfMonth(d: Date): Date {
  const x = startOfDay(d)
  x.setDate(1)
  return x
}

function endOfMonth(d: Date): Date {
  const x = startOfMonth(d)
  x.setMonth(x.getMonth() + 1)
  x.setDate(0)
  return startOfDay(x)
}

function startOfWeek(d: Date): Date {
  const x = startOfDay(d)
  const weekday = (x.getDay() + 6) % 7
  x.setDate(x.getDate() - weekday)
  return x
}

function endOfWeek(d: Date): Date {
  const x = startOfDay(d)
  const weekday = (x.getDay() + 6) % 7
  x.setDate(x.getDate() + (6 - weekday))
  return x
}

function addMonths(d: Date, months: number): Date {
  const x = new Date(d)
  x.setMonth(x.getMonth() + months)
  return startOfMonth(x)
}

