import type { LoadedDatasets } from './localJsonStore'
import { DATA_FILES, DATA_FOLDER_NAME } from './localJsonStore'
import {
  type Account,
  type Bill,
  type Debt,
  type Goal,
  type Income,
  type Transaction,
  iso8601NoMillis,
  parseISO8601,
  type BillAttachment,
  type Invoice,
  type InvoiceAttachment,
  type Payment,
} from '../domain/models'
import type { AppSettings } from '../domain/settings'
import { normalizePeopleSettings } from '../domain/people'

export function isTauriRuntime(): boolean {
  return typeof window !== 'undefined' && typeof (window as any).__TAURI_INTERNALS__ !== 'undefined'
}

async function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const mod = await import('@tauri-apps/api/core')
  return mod.invoke<T>(cmd, args)
}

function safeParseJSON(text: string): unknown {
  return JSON.parse(text) as unknown
}

function safeStringifyJSON(value: unknown): string {
  return JSON.stringify(value, null, 2)
}

export async function appDataDir(): Promise<string> {
  return invoke<string>('app_data_dir')
}

export async function loadAllFromTauriFiles(fallbackSettings: AppSettings): Promise<LoadedDatasets> {
  const settings = normalizePeopleSettings(await loadSettingsFromTauriFiles(fallbackSettings))
  const txLoaded = await loadTransactionsForSettingsFromTauriFiles(settings)
  const settingsWithCounts: AppSettings = {
    ...settings,
    peopleTransactionCounts: { ...settings.peopleTransactionCounts, ...txLoaded.counts },
  }
  return {
    settings: settingsWithCounts,
    bills: await loadArrayFromTauriFiles('bills', decodeBill),
    incomes: await loadArrayFromTauriFiles('incomes', decodeIncome),
    accounts: await loadArrayFromTauriFiles('accounts', decodeAccount),
    transactions: txLoaded.transactions,
    invoices: await loadArrayFromTauriFiles('invoices', decodeInvoice),
    goals: await loadArrayFromTauriFiles('goals', decodeGoal),
    debts: await loadArrayFromTauriFiles('debts', decodeDebt),
  }
}

export async function saveAllToTauriFiles(data: LoadedDatasets): Promise<void> {
  const settings = normalizePeopleSettings(data.settings)
  const settingsWithCounts: AppSettings = {
    ...settings,
    peopleTransactionCounts: { ...settings.peopleTransactionCounts, [settings.activePersonId]: data.transactions.length },
  }
  await saveSettingsToTauriFiles(settingsWithCounts)
  await saveArrayToTauriFiles('bills', data.bills, encodeBill)
  await saveArrayToTauriFiles('incomes', data.incomes, encodeIncome)
  await saveArrayToTauriFiles('accounts', data.accounts, encodeAccount)
  await saveTransactionsForSettingsToTauriFiles(settingsWithCounts, data.transactions)
  await saveArrayToTauriFiles('invoices', data.invoices, encodeInvoice)
  await saveArrayToTauriFiles('goals', data.goals, encodeGoal)
  await saveArrayToTauriFiles('debts', data.debts, encodeDebt)
}

async function readText(name: string): Promise<string | null> {
  const text = await invoke<string | null>('read_data_file', { name })
  return text
}

async function writeText(name: string, text: string): Promise<void> {
  await invoke<void>('write_data_file', { name, content: text })
}

async function preserveCorrupt(name: string): Promise<void> {
  await invoke<void>('preserve_corrupt_file', { name })
}

async function loadSettingsFromTauriFiles(fallback: AppSettings): Promise<AppSettings> {
  const name = DATA_FILES.settings
  const raw = await readText(name)
  if (!raw) return fallback
  try {
    const v = safeParseJSON(raw)
    if (v && typeof v === 'object') return v as AppSettings
    return fallback
  } catch {
    await preserveCorrupt(name)
    return fallback
  }
}

async function saveSettingsToTauriFiles(settings: AppSettings): Promise<void> {
  const name = DATA_FILES.settings
  await writeText(name, safeStringifyJSON(settings))
}

type DataFileKey = Exclude<keyof typeof DATA_FILES, 'settings'>

async function loadArrayFromTauriFiles<T>(file: DataFileKey, decode: (x: unknown) => T): Promise<T[]> {
  const name = DATA_FILES[file]
  const raw = await readText(name)
  if (!raw) return []
  try {
    const v = safeParseJSON(raw)
    if (!Array.isArray(v)) return []
    return v.map(decode)
  } catch {
    await preserveCorrupt(name)
    return []
  }
}

async function saveArrayToTauriFiles<T>(file: DataFileKey, items: T[], encode: (x: T) => unknown): Promise<void> {
  const name = DATA_FILES[file]
  await writeText(name, safeStringifyJSON(items.map(encode)))
}

type EncodedPayment = Omit<Payment, 'date'> & { date: string }
type EncodedBillAttachment = Omit<BillAttachment, 'createdAt'> & { createdAt: string }
type EncodedBill = Omit<Bill, 'nextDueDate' | 'payments' | 'snoozeUntil' | 'attachments'> & {
  nextDueDate: string
  payments: EncodedPayment[]
  snoozeUntil?: string | null
  attachments: EncodedBillAttachment[]
}
type EncodedInvoiceAttachment = Omit<InvoiceAttachment, 'createdAt'> & { createdAt: string }
type EncodedInvoice = Omit<Invoice, 'createdAt' | 'invoiceDate' | 'attachments'> & {
  createdAt: string
  invoiceDate?: string | null
  attachments: EncodedInvoiceAttachment[]
}
type EncodedIncome = Omit<Income, 'nextPayDate' | 'receipts'> & { nextPayDate: string; receipts: EncodedPayment[] }
type EncodedTransaction = Omit<Transaction, 'date'> & { date: string }
type EncodedGoal = Omit<Goal, 'targetDate'> & { targetDate?: string | null }
type EncodedTransactionsEnvelope = { version: 2; byPerson: Record<string, EncodedTransaction[]> }

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

function encodeInvoiceAttachment(a: InvoiceAttachment): EncodedInvoiceAttachment {
  return { ...a, createdAt: iso8601NoMillis(a.createdAt) }
}
function decodeInvoiceAttachment(x: unknown): InvoiceAttachment {
  const o = x as EncodedInvoiceAttachment
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

function encodeInvoice(i: Invoice): EncodedInvoice {
  return {
    ...i,
    createdAt: iso8601NoMillis(i.createdAt),
    invoiceDate: i.invoiceDate ? iso8601NoMillis(i.invoiceDate) : i.invoiceDate ?? null,
    attachments: (i.attachments ?? []).map(encodeInvoiceAttachment),
  }
}
function decodeInvoice(x: unknown): Invoice {
  const o = x as EncodedInvoice
  return {
    ...o,
    createdAt: parseISO8601(o.createdAt),
    invoiceDate: o.invoiceDate ? parseISO8601(o.invoiceDate) : null,
    attachments: (o.attachments ?? []).map(decodeInvoiceAttachment),
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

async function parseEncodedTransactionsRawFromTauriFiles(): Promise<unknown> {
  const raw = await readText(DATA_FILES.transactions)
  if (!raw) return null
  try {
    return safeParseJSON(raw)
  } catch {
    await preserveCorrupt(DATA_FILES.transactions)
    return null
  }
}

function decodeAllByPerson(raw: unknown): { byPerson: Record<string, Transaction[]>; counts: Record<string, number> } {
  if (Array.isArray(raw)) {
    const list = raw.map(decodeTransaction)
    return { byPerson: { legacy: list }, counts: { legacy: list.length } }
  }
  const env = raw as EncodedTransactionsEnvelope
  const obj = env?.byPerson && typeof env.byPerson === 'object' ? env.byPerson : {}
  const byPerson: Record<string, Transaction[]> = {}
  const counts: Record<string, number> = {}
  for (const [pid, arr] of Object.entries(obj)) {
    if (!Array.isArray(arr)) continue
    const list = arr.map(decodeTransaction)
    byPerson[pid] = list
    counts[pid] = list.length
  }
  return { byPerson, counts }
}

export async function loadTransactionsForSettingsFromTauriFiles(settings: AppSettings): Promise<{ transactions: Transaction[]; counts: Record<string, number> }> {
  const normalized = normalizePeopleSettings(settings)
  return loadTransactionsForPersonFromTauriFiles(normalized, normalized.activePersonId)
}

export async function loadTransactionsForPersonFromTauriFiles(
  settings: AppSettings,
  personId: string,
): Promise<{ transactions: Transaction[]; counts: Record<string, number> }> {
  const normalized = normalizePeopleSettings(settings)
  const raw = await parseEncodedTransactionsRawFromTauriFiles()
  const decoded = decodeAllByPerson(raw)
  if (!normalized.peopleEnabled) {
    const all = Object.values(decoded.byPerson).flat()
    return { transactions: all, counts: decoded.counts }
  }
  const pid = String(personId ?? '').trim()
  const active = pid || normalized.activePersonId
  const activeList = decoded.byPerson[active]
  if (activeList) return { transactions: activeList.map((t) => ({ ...t, personId: t.personId || active })), counts: decoded.counts }
  const legacy = decoded.byPerson.legacy ?? []
  if (legacy.length > 0 && active == normalized.activePersonId) {
    const migrated = legacy.map((t) => ({ ...t, personId: active }))
    const counts = { ...decoded.counts, [active]: migrated.length }
    delete (counts as any).legacy
    return { transactions: migrated, counts }
  }
  return { transactions: [], counts: decoded.counts }
}

export async function deletePersonTransactionsFromTauriFiles(personId: string): Promise<void> {
  const pid = String(personId ?? '').trim()
  if (!pid) return
  const raw = await parseEncodedTransactionsRawFromTauriFiles()
  if (!raw || Array.isArray(raw)) return
  const env = raw as EncodedTransactionsEnvelope
  const byPerson = env?.byPerson && typeof env.byPerson === 'object' ? { ...(env.byPerson as any) } : null
  if (!byPerson) return
  if (!(pid in byPerson)) return
  delete byPerson[pid]
  const payload: EncodedTransactionsEnvelope = { version: 2, byPerson }
  await writeText(DATA_FILES.transactions, safeStringifyJSON(payload))
}

export async function saveTransactionsForPersonToTauriFiles(settings: AppSettings, personId: string, transactions: Transaction[]): Promise<void> {
  const normalized = normalizePeopleSettings(settings)
  const pid = String(personId ?? '').trim()
  if (!pid) return
  if (!normalized.peopleEnabled) {
    await writeText(DATA_FILES.transactions, safeStringifyJSON(transactions.map(encodeTransaction)))
    return
  }
  const raw = await parseEncodedTransactionsRawFromTauriFiles()
  const env = raw && !Array.isArray(raw) ? (raw as EncodedTransactionsEnvelope) : null
  const byPerson: Record<string, EncodedTransaction[]> =
    env?.byPerson && typeof env.byPerson === 'object' ? ({ ...(env.byPerson as any) } as any) : {}
  byPerson[pid] = transactions.map((t) => encodeTransaction({ ...t, personId: t.personId || pid }))
  const payload: EncodedTransactionsEnvelope = { version: 2, byPerson }
  await writeText(DATA_FILES.transactions, safeStringifyJSON(payload))
}

async function saveTransactionsForSettingsToTauriFiles(settings: AppSettings, activeTransactions: Transaction[]): Promise<void> {
  const normalized = normalizePeopleSettings(settings)
  if (!normalized.peopleEnabled) {
    await writeText(DATA_FILES.transactions, safeStringifyJSON(activeTransactions.map(encodeTransaction)))
    return
  }
  const existing = decodeAllByPerson(await parseEncodedTransactionsRawFromTauriFiles())
  const byPerson: Record<string, EncodedTransaction[]> = {}
  for (const [pid, tx] of Object.entries(existing.byPerson)) {
    if (pid === 'legacy') continue
    byPerson[pid] = tx.map(encodeTransaction)
  }
  byPerson[normalized.activePersonId] = activeTransactions.map((t) =>
    encodeTransaction({ ...t, personId: t.personId || normalized.activePersonId }),
  )
  const payload: EncodedTransactionsEnvelope = { version: 2, byPerson }
  await writeText(DATA_FILES.transactions, safeStringifyJSON(payload))
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

export const tauriDataFolderHint = DATA_FOLDER_NAME
