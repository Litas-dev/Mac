import type { Transaction, TransactionKind, UUID } from './models'

export interface CsvRow {
  date?: Date
  amount?: number
  description?: string
  memo?: string
  account?: string
}

export function parseCsvRows(content: string): CsvRow[] {
  const records = parseCSV(content).filter((fields) => fields.some((f) => f.trim().length > 0))
  const header = records[0]
  if (!header) return []
  const headers = header.map((h) => h.trim().toLowerCase())
  const map = headerMap(headers)
  const rows: CsvRow[] = []
  for (const fields of records.slice(1)) {
    const row: CsvRow = {}
    row.date = parseDate(field(fields, map.dateIndex))
    row.amount = parseDecimal(field(fields, map.amountIndex))
    row.description = field(fields, map.descriptionIndex)
    row.memo = field(fields, map.memoIndex)
    row.account = field(fields, map.accountIndex)
    rows.push(row)
  }
  return rows
}

export function rowsToTransactions(
  rows: CsvRow[],
  currencyCode: string,
  accountIdResolver: (rawAccount: string | undefined) => UUID | null,
): Transaction[] {
  const tx: Transaction[] = []
  for (const row of rows) {
    if (!row.date || row.amount == null) continue
    const kind: TransactionKind = row.amount < 0 ? 'expense' : 'income'
    const absAmount = row.amount < 0 ? -row.amount : row.amount
    tx.push({
      id: crypto.randomUUID(),
      kind,
      date: row.date,
      amount: { currencyCode, value: absAmount },
      accountId: accountIdResolver(row.account),
      toAccountId: null,
      category: kind === 'expense' ? 'other' : null,
      customCategoryName: null,
      payee: row.description ?? null,
      notes: row.memo ?? null,
      tags: ['bank-csv'],
      relatedBillId: null,
      relatedIncomeId: null,
    })
  }
  return tx
}

interface HeaderMap {
  dateIndex?: number
  amountIndex?: number
  descriptionIndex?: number
  memoIndex?: number
  accountIndex?: number
}

function headerMap(headers: string[]): HeaderMap {
  const idx = (names: string[]): number | undefined => {
    for (const n of names) {
      const i = headers.findIndex((h) => h === n)
      if (i >= 0) return i
    }
    return undefined
  }
  return {
    dateIndex: idx(['date', 'posted date', 'transaction date']),
    amountIndex: idx(['amount', 'transaction amount', 'value']),
    descriptionIndex: idx(['description', 'name', 'payee', 'merchant']),
    memoIndex: idx(['memo', 'notes', 'category']),
    accountIndex: idx(['account', 'account name']),
  }
}

function field(fields: string[], index: number | undefined): string | undefined {
  if (index == null) return undefined
  if (index < 0 || index >= fields.length) return undefined
  const v = fields[index].trim()
  return v.length ? v : undefined
}

export function parseDecimal(input?: string): number | undefined {
  if (!input) return undefined
  let s = input.trim()
  if (!s) return undefined

  let isNegative = false
  if (s.startsWith('(') && s.endsWith(')')) {
    isNegative = true
    s = s.slice(1, -1)
  }

  s = s.replace(/−/g, '-')
  s = s.replace(/[ \u00A0]/g, '')
  for (const sym of ['$', '€', '£', 'NOK', 'SEK', 'DKK', 'USD', 'EUR', 'GBP']) {
    const re = new RegExp(sym, 'ig')
    s = s.replace(re, '')
  }

  const lastComma = s.lastIndexOf(',')
  const lastDot = s.lastIndexOf('.')
  if (lastComma >= 0 && lastDot >= 0) {
    if (lastComma > lastDot) {
      s = s.replace(/\./g, '')
      s = s.replace(/,/g, '.')
    } else {
      s = s.replace(/,/g, '')
    }
  } else if (lastComma >= 0) {
    s = s.replace(/,/g, '.')
  }

  if (s.startsWith('+')) s = s.slice(1)
  const n = Number(s)
  if (!Number.isFinite(n)) return undefined
  return isNegative ? -n : n
}

export function parseDate(input?: string): Date | undefined {
  if (!input) return undefined
  const trimmed = input.trim()
  if (!trimmed) return undefined

  const iso = new Date(trimmed)
  if (Number.isFinite(iso.getTime())) return iso

  if (trimmed.includes('/')) {
    const parts = trimmed.split('/')
    if (parts.length === 3) {
      const a = Number(parts[0])
      const b = Number(parts[1])
      const y = Number(parts[2])
      if (Number.isFinite(a) && Number.isFinite(b) && Number.isFinite(y)) {
        if (a > 12) return new Date(y, b - 1, a)
        if (b > 12) return new Date(y, a - 1, b)
      }
    }
  }

  const formats = [
    /^(\d{4})-(\d{2})-(\d{2})$/,
    /^(\d{4})\/(\d{2})\/(\d{2})$/,
    /^(\d{2})\/(\d{2})\/(\d{4})$/,
  ]
  for (const re of formats) {
    const m = trimmed.match(re)
    if (!m) continue
    if (re === formats[0] || re === formats[1]) {
      const y = Number(m[1])
      const mo = Number(m[2])
      const d = Number(m[3])
      return new Date(y, mo - 1, d)
    }
    const a = Number(m[1])
    const b = Number(m[2])
    const y = Number(m[3])
    if (a > 12) return new Date(y, b - 1, a)
    return new Date(y, a - 1, b)
  }

  return undefined
}

function parseCSV(content: string): string[][] {
  const rows: string[][] = []
  let row: string[] = []
  let field = ''
  let inQuotes = false

  for (let i = 0; i < content.length; i++) {
    const ch = content[i]!
    if (ch === '"') {
      const next = content[i + 1]
      if (inQuotes && next === '"') {
        field += '"'
        i++
        continue
      }
      inQuotes = !inQuotes
      continue
    }
    if (!inQuotes && (ch === ',' || ch === '\n' || ch === '\r')) {
      row.push(field)
      field = ''
      if (ch === '\n') {
        rows.push(row)
        row = []
      } else if (ch === '\r') {
        const next = content[i + 1]
        if (next === '\n') i++
        rows.push(row)
        row = []
      }
      continue
    }
    field += ch
  }
  row.push(field)
  if (row.length > 1 || row[0]?.trim()) rows.push(row)
  return rows
}

