import { useMemo, useState } from 'react'
import { useAppStore } from '../../app/appStore'
import { advanceRecurrence, billIsPaidFor, billIsSnoozedActive } from '../../domain/models'

type DayItem = { kind: 'bill' | 'income' | 'reminder'; title: string; id?: string; priority?: 'low' | 'medium' | 'high' | 'critical' }

export function CalendarView() {
  const { state, dispatch } = useAppStore()
  const [cursor, setCursor] = useState(() => startOfMonth(new Date()))
  const [openDay, setOpenDay] = useState<Date | null>(null)
  const [editingReminderId, setEditingReminderId] = useState<string | null>(null)
  const [showCompleted, setShowCompleted] = useState(false)
  const [formTitle, setFormTitle] = useState('')
  const [formDate, setFormDate] = useState('')
  const [formTime, setFormTime] = useState('')
  const [formAllDay, setFormAllDay] = useState(true)
  const [formNotes, setFormNotes] = useState('')
  const [formRemind, setFormRemind] = useState<string>('15')
  const [formImportance, setFormImportance] = useState<'green' | 'yellow' | 'red'>('yellow')

  const monthLabel = useMemo(() => cursor.toLocaleString(undefined, { month: 'long', year: 'numeric' }), [cursor])

  const editingReminder = useMemo(() => {
    if (!editingReminderId || editingReminderId === '__new__') return null
    return state.reminders.find((r) => r.id === editingReminderId) ?? null
  }, [editingReminderId, state.reminders])

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
    const rangeStart = startOfWeek(startOfMonth(cursor))
    const rangeEndExclusive = addDays(endOfWeek(endOfMonth(cursor)), 1)
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
    const peopleEnabled = Boolean(state.settings.peopleEnabled)
    const activePersonId = String(state.settings.activePersonId || '').trim()
    for (const r of state.reminders) {
      const pid = r.personId ? String(r.personId).trim() : ''
      if (peopleEnabled && pid && pid !== activePersonId) continue
      if (r.recurrence === 'once' && r.completedAt) continue
      const occ = reminderOccurrencesInRange(r, rangeStart, rangeEndExclusive)
      for (const when of occ) {
        const key = startOfDay(when).getTime()
        const arr = map.get(key) ?? []
        arr.push({ kind: 'reminder', title: r.title, id: r.id, priority: r.priority })
        map.set(key, arr)
      }
    }
    return map
  }, [cursor, state.bills, state.incomes, state.reminders, state.settings.activePersonId, state.settings.peopleEnabled])

  const openDayItems = useMemo(() => {
    if (!openDay) return []
    const dayStart = startOfDay(openDay)
    const dayEnd = addDays(dayStart, 1)
    const list: Array<{
      kind: 'bill' | 'income' | 'reminder'
      id?: string
      title: string
      timeLabel?: string
      notes?: string
      completed?: boolean
      priority?: 'low' | 'medium' | 'high' | 'critical'
    }> = []

    const now = new Date()
    for (const b of state.bills) {
      if (b.hiddenUntilEdited) continue
      if (billIsSnoozedActive(b, now)) continue
      if (billIsPaidFor(b, b.nextDueDate)) continue
      const d = startOfDay(b.nextDueDate)
      if (d.getTime() !== dayStart.getTime()) continue
      list.push({ kind: 'bill', title: b.name })
    }
    for (const inc of state.incomes) {
      const d = startOfDay(inc.nextPayDate)
      if (d.getTime() !== dayStart.getTime()) continue
      list.push({ kind: 'income', title: inc.name })
    }

    const peopleEnabled = Boolean(state.settings.peopleEnabled)
    const activePersonId = String(state.settings.activePersonId || '').trim()
    for (const r of state.reminders) {
      const pid = r.personId ? String(r.personId).trim() : ''
      if (peopleEnabled && pid && pid !== activePersonId) continue
      if (r.recurrence === 'once') {
        if (!showCompleted && r.completedAt) continue
        if (r.when.getTime() < dayStart.getTime() || r.when.getTime() >= dayEnd.getTime()) continue
        const timeLabel = r.allDay ? 'All day' : formatTime(r.when)
        list.push({
          kind: 'reminder',
          id: r.id,
          title: r.title,
          timeLabel,
          notes: r.notes || '',
          completed: Boolean(r.completedAt),
          priority: r.priority,
        })
        continue
      }

      const occ = reminderOccurrencesInRange(r, dayStart, dayEnd)
      for (const when of occ) {
        const timeLabel = r.allDay ? 'All day' : formatTime(when)
        list.push({ kind: 'reminder', id: r.id, title: r.title, timeLabel, notes: r.notes || '', completed: false, priority: r.priority })
      }
    }

    return list
  }, [openDay, showCompleted, state.bills, state.incomes, state.reminders, state.settings.activePersonId, state.settings.peopleEnabled])

  function openNewReminderForDay(day: Date) {
    const d = startOfDay(day)
    setOpenDay(d)
    setEditingReminderId('__new__')
    setFormTitle('')
    setFormDate(toDateInputValue(d))
    setFormTime('')
    setFormAllDay(true)
    setFormNotes('')
    setFormRemind('15')
    setFormImportance('yellow')
  }

  function openEditReminder(reminderId: string) {
    const r = state.reminders.find((x) => x.id === reminderId)
    if (!r) return
    setEditingReminderId(reminderId)
    setFormTitle(r.title || '')
    setFormDate(toDateInputValue(r.when))
    setFormTime(r.allDay ? '' : toTimeInputValue(r.when))
    setFormAllDay(Boolean(r.allDay))
    setFormNotes(String(r.notes || ''))
    const hasMulti = Array.isArray(r.remindMinutesBeforeList) && r.remindMinutesBeforeList.length > 0
    setFormRemind(hasMulti ? '__multi__' : r.remindMinutesBefore == null ? '' : String(r.remindMinutesBefore))
    setFormImportance(priorityToImportance(r.priority))
  }

  function closeDayModal() {
    setOpenDay(null)
    setEditingReminderId(null)
  }

  function parseFormWhen(): Date | null {
    const d = parseDateInput(formDate)
    if (!d) return null
    const when = new Date(d)
    if (formAllDay) {
      when.setHours(0, 0, 0, 0)
      return when
    }
    const t = parseTimeInput(formTime)
    if (t) {
      when.setHours(t.h, t.m, 0, 0)
      return when
    }
    when.setHours(9, 0, 0, 0)
    return when
  }

  function saveReminder() {
    const title = String(formTitle || '').trim()
    if (!title) return
    const when = parseFormWhen()
    if (!when) return
    const now = new Date()
    const peopleEnabled = Boolean(state.settings.peopleEnabled)
    const personId = peopleEnabled ? state.settings.activePersonId : null
    const isMulti = formRemind === '__multi__'
    const remindMinutesBefore = !isMulti && formRemind !== '' ? Number(formRemind) : null
    const normalizedRemind = remindMinutesBefore == null || !Number.isFinite(remindMinutesBefore) ? null : remindMinutesBefore

    if (editingReminderId && editingReminderId !== '__new__') {
      const existing = state.reminders.find((x) => x.id === editingReminderId)
      if (!existing) return
      const nextPriority = importanceToPriority(formImportance)
      dispatch({
        type: 'reminders/update',
        reminder: {
          ...existing,
          title,
          when,
          allDay: Boolean(formAllDay),
          priority: existing.priority === 'critical' && formImportance === 'red' ? 'critical' : nextPriority,
          notes: String(formNotes || '').trim() || null,
          remindMinutesBefore: isMulti ? null : normalizedRemind,
          remindMinutesBeforeList: isMulti ? existing.remindMinutesBeforeList ?? null : null,
          personId: existing.personId ?? personId,
        },
      })
    } else {
      dispatch({
        type: 'reminders/add',
        reminder: {
          id: crypto.randomUUID(),
          title,
          when,
          allDay: Boolean(formAllDay),
          recurrence: 'once',
          priority: importanceToPriority(formImportance),
          notes: String(formNotes || '').trim() || null,
          remindMinutesBefore: normalizedRemind,
          remindMinutesBeforeList: null,
          completedAt: null,
          personId,
          createdAt: now,
        },
      })
    }
    setEditingReminderId(null)
  }

  function deleteReminder(id: string) {
    dispatch({ type: 'reminders/delete', id })
    if (editingReminderId === id) setEditingReminderId(null)
  }

  function toggleReminderComplete(id: string, nextCompleted: boolean) {
    dispatch({ type: 'reminders/toggleComplete', id, completed: nextCompleted })
  }

  return (
    <div className="calendar">
      <div className="calendarTop">
        <div className="calendarTitle">{monthLabel}</div>
        <div className="rowActions">
          <button type="button" onClick={() => openNewReminderForDay(new Date())}>
            New reminder
          </button>
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
          const isWeekend = d.getDay() === 0 || d.getDay() === 6
          const key = startOfDay(d).getTime()
          const items = itemsByDay.get(key) ?? []
          return (
            <button
              type="button"
              key={key}
              className={`calendarDay ${inMonth ? '' : 'outside'} ${isWeekend ? 'weekend' : ''}`}
              title={items.length > 0 ? items.slice(0, 10).map((x) => x.title).join(' • ') : ''}
              onClick={() => {
                setOpenDay(startOfDay(d))
                setEditingReminderId(null)
                setFormDate(toDateInputValue(d))
              }}
              style={{ textAlign: 'left', cursor: 'pointer' }}
            >
              <div className="calendarDayNum">{d.getDate()}</div>
              {items.slice(0, 3).map((it, idx) => (
                <div
                  key={idx}
                  className={`calendarPill calendarPillCompact ${it.kind}`}
                  data-priority={it.kind === 'reminder' ? it.priority : undefined}
                  title={it.title}
                >
                  {compactLabel(it.title, 18)}
                </div>
              ))}
              {items.length > 3 ? <div className="calendarMore">+{items.length - 3}</div> : null}
            </button>
          )
        })}
      </div>

      {openDay ? (
        <div className="modalBackdrop" onMouseDown={closeDayModal}>
          <div className="modal" onMouseDown={(e) => e.stopPropagation()}>
            <div className="modalTitle">{formatLongDate(openDay)}</div>

            {editingReminderId ? (
              <>
                <div className="form" style={{ marginTop: 10 }}>
                  <div className="fieldRow">
                    <label className="field">
                      <div className="fieldLabel">Title</div>
                      <input value={formTitle} onChange={(e) => setFormTitle(e.target.value)} />
                    </label>
                    <label className="field">
                      <div className="fieldLabel">Date</div>
                      <input type="date" value={formDate} onChange={(e) => setFormDate(e.target.value)} />
                    </label>
                  </div>
                  <div className="fieldRow" style={{ marginTop: 10 }}>
                    <label className="field">
                      <div className="fieldLabel">All day</div>
                      <select value={formAllDay ? '1' : '0'} onChange={(e) => setFormAllDay(e.target.value === '1')}>
                        <option value="1">Yes</option>
                        <option value="0">No</option>
                      </select>
                    </label>
                    <label className="field">
                      <div className="fieldLabel">Time</div>
                      <input type="time" value={formTime} onChange={(e) => setFormTime(e.target.value)} disabled={formAllDay} />
                    </label>
                  </div>
                  <div className="fieldRow" style={{ marginTop: 10 }}>
                    <label className="field">
                      <div className="fieldLabel">Notify</div>
                      <select value={formRemind} onChange={(e) => setFormRemind(e.target.value)}>
                        <option value="">None</option>
                        {editingReminder && Array.isArray(editingReminder.remindMinutesBeforeList) && editingReminder.remindMinutesBeforeList.length > 0 ? (
                          <option value="__multi__">Multiple reminders</option>
                        ) : null}
                        <option value="0">At time</option>
                        <option value="5">5 minutes before</option>
                        <option value="15">15 minutes before</option>
                        <option value="60">1 hour before</option>
                        <option value="1440">1 day before</option>
                        <option value="7200">5 days before</option>
                        <option value="21600">15 days before</option>
                      </select>
                    </label>
                    <label className="field">
                      <div className="fieldLabel">Importance</div>
                      <select value={formImportance} onChange={(e) => setFormImportance(e.target.value as any)}>
                        <option value="green">Green</option>
                        <option value="yellow">Yellow</option>
                        <option value="red">Red</option>
                      </select>
                    </label>
                  </div>
                  <label className="field" style={{ marginTop: 10 }}>
                    <div className="fieldLabel">Note</div>
                    <textarea value={formNotes} onChange={(e) => setFormNotes(e.target.value)} rows={3} />
                  </label>
                </div>
                <div className="modalActions">
                  <button type="button" onClick={() => setEditingReminderId(null)}>
                    Back
                  </button>
                  <button type="button" onClick={saveReminder}>
                    Save
                  </button>
                </div>
              </>
            ) : (
              <>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 10, gap: 12 }}>
                  <div className="note">{openDayItems.length > 0 ? `${openDayItems.length} item(s)` : 'No items for this day.'}</div>
                  <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                    <label className="check" style={{ margin: 0 }}>
                      <input type="checkbox" checked={showCompleted} onChange={(e) => setShowCompleted(e.target.checked)} />
                      Show completed
                    </label>
                    <button type="button" onClick={() => openNewReminderForDay(openDay)}>
                      Add reminder
                    </button>
                  </div>
                </div>

                <div style={{ marginTop: 10, display: 'flex', flexDirection: 'column', gap: 8 }}>
                  {openDayItems.map((it, idx) => {
                    if (it.kind !== 'reminder') {
                      return (
                        <div key={`${it.kind}-${idx}`} className={`calendarPill ${it.kind}`} title={it.title}>
                          {it.title}
                        </div>
                      )
                    }
                    return (
                      <div key={it.id || idx} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                        <div
                          className="calendarPill reminder"
                          data-priority={it.priority}
                          style={{ flex: '1 1 auto', opacity: it.completed ? 0.6 : 1 }}
                          title={it.title}
                        >
                          <span style={{ fontWeight: 700 }}>{it.timeLabel}</span> • {it.title}
                        </div>
                        <button type="button" onClick={() => toggleReminderComplete(it.id!, !it.completed)} style={{ padding: '6px 10px' }}>
                          {it.completed ? 'Undo' : 'Done'}
                        </button>
                        <button type="button" onClick={() => openEditReminder(it.id!)} style={{ padding: '6px 10px' }}>
                          Edit
                        </button>
                        <button type="button" onClick={() => deleteReminder(it.id!)} style={{ padding: '6px 10px' }}>
                          Delete
                        </button>
                      </div>
                    )
                  })}
                </div>

                <div className="modalActions">
                  <button type="button" onClick={closeDayModal}>
                    Close
                  </button>
                </div>
              </>
            )}
          </div>
        </div>
      ) : null}
    </div>
  )
}

function priorityToImportance(p: 'low' | 'medium' | 'high' | 'critical'): 'green' | 'yellow' | 'red' {
  if (p === 'low') return 'green'
  if (p === 'medium') return 'yellow'
  return 'red'
}

function importanceToPriority(i: 'green' | 'yellow' | 'red'): 'low' | 'medium' | 'high' {
  if (i === 'green') return 'low'
  if (i === 'yellow') return 'medium'
  return 'high'
}

function startOfDay(d: Date): Date {
  const x = new Date(d)
  x.setHours(0, 0, 0, 0)
  return x
}

function addDays(d: Date, days: number): Date {
  const x = new Date(d)
  x.setDate(x.getDate() + days)
  return x
}

function toDateInputValue(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

function toTimeInputValue(d: Date): string {
  const hh = String(d.getHours()).padStart(2, '0')
  const mm = String(d.getMinutes()).padStart(2, '0')
  return `${hh}:${mm}`
}

function parseDateInput(v: string): Date | null {
  const s = String(v || '').trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null
  const [y, m, d] = s.split('-').map((x) => Number(x))
  if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d)) return null
  const out = new Date(y, m - 1, d, 0, 0, 0, 0)
  if (Number.isNaN(out.getTime())) return null
  return out
}

function parseTimeInput(v: string): { h: number; m: number } | null {
  const s = String(v || '').trim()
  if (!s) return null
  const parts = s.split(':')
  if (parts.length < 2) return null
  const h = Number(parts[0])
  const m = Number(parts[1])
  if (!Number.isFinite(h) || !Number.isFinite(m)) return null
  if (h < 0 || h > 23) return null
  if (m < 0 || m > 59) return null
  return { h, m }
}

function formatTime(d: Date): string {
  try {
    return new Intl.DateTimeFormat(undefined, { hour: '2-digit', minute: '2-digit' }).format(d)
  } catch {
    return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
  }
}

function formatLongDate(d: Date): string {
  try {
    return new Intl.DateTimeFormat(undefined, { weekday: 'long', year: 'numeric', month: 'long', day: '2-digit' }).format(d)
  } catch {
    return d.toDateString()
  }
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

function reminderOccurrencesInRange(reminder: { when: Date; allDay: boolean; recurrence: string }, start: Date, endExclusive: Date): Date[] {
  const out: Date[] = []
  const startDay = startOfDay(start)
  const endDay = startOfDay(endExclusive)

  let cursor = new Date(reminder.when)
  if (reminder.allDay) cursor = startOfDay(cursor)

  const recurrence = reminder.recurrence
  if (recurrence === 'once') {
    if (cursor.getTime() >= startDay.getTime() && cursor.getTime() < endDay.getTime()) out.push(cursor)
    return out
  }

  let guardrail = 0
  while (cursor.getTime() < startDay.getTime() && guardrail < 1000) {
    const next = advanceRecurrence(recurrence as any, cursor)
    if (next.getTime() === cursor.getTime()) break
    cursor = reminder.allDay ? startOfDay(next) : next
    guardrail += 1
  }

  guardrail = 0
  while (cursor.getTime() < endDay.getTime() && guardrail < 200) {
    if (cursor.getTime() >= startDay.getTime()) out.push(new Date(cursor))
    const next = advanceRecurrence(recurrence as any, cursor)
    if (next.getTime() === cursor.getTime()) break
    cursor = reminder.allDay ? startOfDay(next) : next
    guardrail += 1
  }
  return out
}

function compactLabel(s: string, maxChars: number): string {
  const raw = String(s ?? '').trim()
  if (!raw) return ''
  const max = Math.max(4, Math.floor(Number(maxChars) || 0))
  if (raw.length <= max) return raw
  return raw.slice(0, Math.max(0, max - 1)).trimEnd() + '…'
}
