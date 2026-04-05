import type { Bill } from '../domain/models'
import { billIsPaidFor, billIsSnoozedActive } from '../domain/models'
import type { AppSettings } from '../domain/settings'
import { isTauriRuntime } from '../storage/tauriJsonStore'

type TimerId = number

let timers: TimerId[] = []

export function clearScheduledNotifications() {
  for (const t of timers) window.clearTimeout(t)
  timers = []
}

export async function scheduleAllNotifications(bills: Bill[], settings: AppSettings, now: Date = new Date()) {
  clearScheduledNotifications()
  if (!settings.enableNotifications) return
  if (!isTauriRuntime()) return

  const upcoming = computeUpcoming(bills, settings, now).slice(0, 50)
  if (upcoming.length === 0) return

  for (const item of upcoming) {
    const delay = item.fireAt.getTime() - now.getTime()
    if (delay <= 0) continue
    const id = window.setTimeout(() => {
      void sendNotification(item.title, item.body)
    }, delay)
    timers.push(id)
  }
}

async function sendNotification(title: string, body: string) {
  if (!isTauriRuntime()) return
  const mod = await import('@tauri-apps/plugin-notification')
  await mod.sendNotification({ title, body })
}

function computeUpcoming(
  bills: Bill[],
  settings: AppSettings,
  now: Date,
): Array<{ fireAt: Date; title: string; body: string }> {
  const list: Array<{ fireAt: Date; title: string; body: string }> = []
  const reminderDays = settings.reminderDays ?? 7

  for (const bill of bills) {
    if (bill.hiddenUntilEdited) continue
    if (billIsSnoozedActive(bill, now)) continue
    if (billIsPaidFor(bill, bill.nextDueDate)) continue

    const due = startOfDay(bill.nextDueDate)
    let fire = addDays(due, -reminderDays)
    if (fire.getTime() < startOfDay(now).getTime()) {
      fire = due
    }
    fire.setHours(9, 0, 0, 0)
    if (fire.getTime() <= now.getTime()) continue

    list.push({
      fireAt: fire,
      title: `Bill due: ${bill.name}`,
      body: `${formatDate(bill.nextDueDate)} • ${bill.amount.currencyCode} ${bill.amount.value}`,
    })
  }

  return list.sort((a, b) => a.fireAt.getTime() - b.fireAt.getTime())
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

function formatDate(d: Date): string {
  try {
    return new Intl.DateTimeFormat(undefined, { year: 'numeric', month: 'short', day: '2-digit' }).format(d)
  } catch {
    return d.toDateString()
  }
}
