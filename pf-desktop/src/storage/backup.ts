import type { LoadedDatasets } from './localJsonStore'
import type { Bill, BillAttachment, Income, Invoice, InvoiceAttachment, Payment, Transaction, Goal, Debt } from '../domain/models'
import { iso8601NoMillis, parseISO8601 } from '../domain/models'
import { defaultSettings, migratedBudgetCategories, migratedBudgets, type AppSettings } from '../domain/settings'

export interface DataBackupHeader {
  version: number
}

export interface DataBackupV1 extends DataBackupHeader {
  version: 1
  exportedAt: string
  settings: AppSettings
  bills: EncodedBill[]
  incomes: EncodedIncome[]
}

export interface DataBackupV2 extends DataBackupHeader {
  version: 2
  exportedAt: string
  settings: AppSettings
  bills: EncodedBill[]
  incomes: EncodedIncome[]
  accounts: unknown[]
  transactions: EncodedTransaction[]
  goals: EncodedGoal[]
  debts: unknown[]
}

export interface DataBackupV3 extends DataBackupHeader {
  version: 3
  exportedAt: string
  settings: AppSettings
  bills: EncodedBill[]
  incomes: EncodedIncome[]
  accounts: unknown[]
  transactions: EncodedTransaction[]
  invoices: EncodedInvoice[]
  goals: EncodedGoal[]
  debts: unknown[]
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

export function encodeBackupV3(datasets: LoadedDatasets): string {
  const payload: DataBackupV3 = {
    version: 3,
    exportedAt: iso8601NoMillis(new Date()),
    settings: datasets.settings,
    bills: datasets.bills.map(encodeBill),
    incomes: datasets.incomes.map(encodeIncome),
    accounts: datasets.accounts,
    transactions: datasets.transactions.map(encodeTransaction),
    invoices: datasets.invoices.map(encodeInvoice),
    goals: datasets.goals.map(encodeGoal),
    debts: datasets.debts,
  }
  return JSON.stringify(payload, null, 2)
}

export function encodeBackupV2(datasets: LoadedDatasets): string {
  return encodeBackupV3(datasets)
}

export function decodeBackupToDatasets(jsonText: string): { version: number; datasets: LoadedDatasets } {
  const raw = JSON.parse(jsonText) as any
  const version = Number(raw?.version ?? 0)
  const base = migratedBudgetCategories(migratedBudgets({ ...defaultSettings(), ...(raw?.settings ?? {}) }))

  if (version === 1) {
    const bills: Bill[] = Array.isArray(raw?.bills) ? raw.bills.map(decodeBill) : []
    const incomes: Income[] = Array.isArray(raw?.incomes) ? raw.incomes.map(decodeIncome) : []
    return {
      version,
      datasets: {
        settings: base,
        bills,
        incomes,
        accounts: [],
        transactions: [],
        invoices: [],
        goals: [],
        debts: [],
      },
    }
  }

  if (version === 2) {
    const bills: Bill[] = Array.isArray(raw?.bills) ? raw.bills.map(decodeBill) : []
    const incomes: Income[] = Array.isArray(raw?.incomes) ? raw.incomes.map(decodeIncome) : []
    const transactions: Transaction[] = Array.isArray(raw?.transactions) ? raw.transactions.map(decodeTransaction) : []
    const goals: Goal[] = Array.isArray(raw?.goals) ? raw.goals.map(decodeGoal) : []
    const debts: Debt[] = Array.isArray(raw?.debts) ? (raw.debts as Debt[]) : []
    const accounts = Array.isArray(raw?.accounts) ? raw.accounts : []
    return {
      version,
      datasets: {
        settings: base,
        bills,
        incomes,
        accounts: accounts as any,
        transactions,
        invoices: [],
        goals,
        debts,
      },
    }
  }

  if (version === 3) {
    const bills: Bill[] = Array.isArray(raw?.bills) ? raw.bills.map(decodeBill) : []
    const incomes: Income[] = Array.isArray(raw?.incomes) ? raw.incomes.map(decodeIncome) : []
    const transactions: Transaction[] = Array.isArray(raw?.transactions) ? raw.transactions.map(decodeTransaction) : []
    const invoices: Invoice[] = Array.isArray(raw?.invoices) ? raw.invoices.map(decodeInvoice) : []
    const goals: Goal[] = Array.isArray(raw?.goals) ? raw.goals.map(decodeGoal) : []
    const debts: Debt[] = Array.isArray(raw?.debts) ? (raw.debts as Debt[]) : []
    const accounts = Array.isArray(raw?.accounts) ? raw.accounts : []
    return {
      version,
      datasets: {
        settings: base,
        bills,
        incomes,
        accounts: accounts as any,
        transactions,
        invoices,
        goals,
        debts,
      },
    }
  }

  throw new Error('Unsupported backup version')
}

export function attachmentPathsForBackup(datasets: LoadedDatasets): string[] {
  const paths: string[] = []
  for (const b of datasets.bills) {
    for (const a of b.attachments ?? []) {
      if (a.storedRelativePath) paths.push(a.storedRelativePath)
    }
  }
  for (const inv of datasets.invoices) {
    for (const a of inv.attachments ?? []) {
      if (a.storedRelativePath) paths.push(a.storedRelativePath)
    }
  }
  return Array.from(new Set(paths))
}
