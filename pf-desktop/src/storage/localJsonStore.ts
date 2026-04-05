import {
  type Account,
  type Bill,
  type BillAttachment,
  type Debt,
  type Goal,
  type Income,
  type Payment,
  type Transaction,
  iso8601NoMillis,
  parseISO8601,
} from '../domain/models'
import type { AppSettings } from '../domain/settings'

export const DATA_FOLDER_NAME = 'Kivana'

export const DATA_FILES = {
  bills: 'bills.json',
  incomes: 'incomes.json',
  accounts: 'accounts.json',
  transactions: 'transactions.json',
  goals: 'goals.json',
  debts: 'debts.json',
  settings: 'settings.json',
} as const

type DataFileKey = keyof typeof DATA_FILES

function storageKey(fileName: string): string {
  return `${DATA_FOLDER_NAME}/${fileName}`
}

function safeParseJSON(text: string): unknown {
  return JSON.parse(text) as unknown
}

function safeStringifyJSON(value: unknown): string {
  return JSON.stringify(value, null, 2)
}

export interface LoadedDatasets {
  settings: AppSettings
  bills: Bill[]
  incomes: Income[]
  accounts: Account[]
  transactions: Transaction[]
  goals: Goal[]
  debts: Debt[]
}

export function loadAllFromLocalStorage(fallbackSettings: AppSettings): LoadedDatasets {
  return {
    settings: loadSettingsFromLocalStorage(fallbackSettings),
    bills: loadArrayFromLocalStorage('bills', decodeBill),
    incomes: loadArrayFromLocalStorage('incomes', decodeIncome),
    accounts: loadArrayFromLocalStorage('accounts', decodeAccount),
    transactions: loadArrayFromLocalStorage('transactions', decodeTransaction),
    goals: loadArrayFromLocalStorage('goals', decodeGoal),
    debts: loadArrayFromLocalStorage('debts', decodeDebt),
  }
}

export function saveAllToLocalStorage(data: LoadedDatasets): void {
  saveSettingsToLocalStorage(data.settings)
  saveArrayToLocalStorage('bills', data.bills, encodeBill)
  saveArrayToLocalStorage('incomes', data.incomes, encodeIncome)
  saveArrayToLocalStorage('accounts', data.accounts, encodeAccount)
  saveArrayToLocalStorage('transactions', data.transactions, encodeTransaction)
  saveArrayToLocalStorage('goals', data.goals, encodeGoal)
  saveArrayToLocalStorage('debts', data.debts, encodeDebt)
}

export function loadSettingsFromLocalStorage(fallback: AppSettings): AppSettings {
  const key = storageKey(DATA_FILES.settings)
  const raw = localStorage.getItem(key)
  if (!raw) return fallback
  try {
    const v = safeParseJSON(raw)
    if (v && typeof v === 'object') {
      return v as AppSettings
    }
    return fallback
  } catch {
    preserveCorruptItem(key)
    return fallback
  }
}

export function saveSettingsToLocalStorage(settings: AppSettings): void {
  const key = storageKey(DATA_FILES.settings)
  localStorage.setItem(key, safeStringifyJSON(settings))
}

function loadArrayFromLocalStorage<T>(file: DataFileKey, decode: (x: unknown) => T): T[] {
  const key = storageKey(DATA_FILES[file])
  const raw = localStorage.getItem(key)
  if (!raw) return []
  try {
    const v = safeParseJSON(raw)
    if (!Array.isArray(v)) return []
    return v.map(decode)
  } catch {
    preserveCorruptItem(key)
    return []
  }
}

function saveArrayToLocalStorage<T>(file: DataFileKey, items: T[], encode: (x: T) => unknown): void {
  const key = storageKey(DATA_FILES[file])
  localStorage.setItem(key, safeStringifyJSON(items.map(encode)))
}

function preserveCorruptItem(key: string): void {
  try {
    const now = iso8601NoMillis(new Date()).replace(/[:]/g, '-')
    const backupKey = `${key}.corrupt-${now}`
    const raw = localStorage.getItem(key)
    if (raw != null) localStorage.setItem(backupKey, raw)
  } catch {
  }
}

type EncodedPayment = Omit<Payment, 'date'> & { date: string }
type EncodedBillAttachment = Omit<BillAttachment, 'createdAt'> & { createdAt: string }
type EncodedBill = Omit<Bill, 'nextDueDate' | 'payments' | 'snoozeUntil' | 'attachments'> & {
  nextDueDate: string
  payments: EncodedPayment[]
  snoozeUntil?: string | null
  attachments: EncodedBillAttachment[]
}
type EncodedIncome = Omit<Income, 'nextPayDate' | 'receipts'> & { nextPayDate: string; receipts: EncodedPayment[] }
type EncodedTransaction = Omit<Transaction, 'date'> & { date: string }
type EncodedGoal = Omit<Goal, 'targetDate'> & { targetDate?: string | null }

function encodePayment(p: Payment): EncodedPayment {
  return { ...p, date: iso8601NoMillis(p.date) }
}
function decodePayment(x: unknown): Payment {
  const o = x as EncodedPayment
  return { ...o, date: parseISO8601(o.date) }
}

function encodeBillAttachment(a: BillAttachment): EncodedBillAttachment {
  return { ...a, createdAt: iso8601NoMillis(a.createdAt) }
}
function decodeBillAttachment(x: unknown): BillAttachment {
  const o = x as EncodedBillAttachment
  return { ...o, createdAt: parseISO8601(o.createdAt) }
}

function encodeBill(b: Bill): EncodedBill {
  return {
    ...b,
    nextDueDate: iso8601NoMillis(b.nextDueDate),
    payments: b.payments.map(encodePayment),
    snoozeUntil: b.snoozeUntil ? iso8601NoMillis(b.snoozeUntil) : b.snoozeUntil,
    attachments: b.attachments.map(encodeBillAttachment),
  }
}
function decodeBill(x: unknown): Bill {
  const o = x as EncodedBill
  return {
    ...o,
    nextDueDate: parseISO8601(o.nextDueDate),
    payments: (o.payments ?? []).map(decodePayment),
    snoozeUntil: o.snoozeUntil ? parseISO8601(o.snoozeUntil) : null,
    attachments: (o.attachments ?? []).map(decodeBillAttachment),
  }
}

function encodeIncome(i: Income): EncodedIncome {
  return {
    ...i,
    nextPayDate: iso8601NoMillis(i.nextPayDate),
    receipts: i.receipts.map(encodePayment),
  }
}
function decodeIncome(x: unknown): Income {
  const o = x as EncodedIncome
  return {
    ...o,
    nextPayDate: parseISO8601(o.nextPayDate),
    receipts: (o.receipts ?? []).map(decodePayment),
  }
}

function encodeAccount(a: Account): Account {
  return a
}
function decodeAccount(x: unknown): Account {
  return x as Account
}

function encodeTransaction(t: Transaction): EncodedTransaction {
  return { ...t, date: iso8601NoMillis(t.date) }
}
function decodeTransaction(x: unknown): Transaction {
  const o = x as EncodedTransaction
  return { ...o, date: parseISO8601(o.date), tags: o.tags ?? [] }
}

function encodeGoal(g: Goal): EncodedGoal {
  return { ...g, targetDate: g.targetDate ? iso8601NoMillis(g.targetDate) : g.targetDate ?? null }
}
function decodeGoal(x: unknown): Goal {
  const o = x as EncodedGoal
  return { ...o, targetDate: o.targetDate ? parseISO8601(o.targetDate) : null }
}

function encodeDebt(d: Debt): Debt {
  return d
}
function decodeDebt(x: unknown): Debt {
  return x as Debt
}
