import type { Transaction, UUID } from './models'
import { parseCsvRows, parseDate, parseDecimal, rowsToTransactions } from './csvImport'
import type { CsvRow } from './csvImport'

type PdfTextItem = { str: string; hasEOL?: boolean; transform: number[] }

export async function convertPdfToCsvString(file: File): Promise<string> {
  const pdfjs: any = await import('pdfjs-dist/legacy/build/pdf.mjs')
  pdfjs.GlobalWorkerOptions.workerSrc = new URL('pdfjs-dist/legacy/build/pdf.worker.mjs', import.meta.url).toString()

  const data = new Uint8Array(await file.arrayBuffer())
  const doc = await pdfjs.getDocument({ data }).promise
  
  type StatementPeriod = { start: Date; end: Date }
  let period: StatementPeriod | null = null

  function monthIndexFromAbbrev(input: string): number | null {
    const m = input.trim().slice(0, 3).toLowerCase()
    const map: Record<string, number> = {
      jan: 0,
      feb: 1,
      mar: 2,
      apr: 3,
      may: 4,
      jun: 5,
      jul: 6,
      aug: 7,
      sep: 8,
      oct: 9,
      nov: 10,
      dec: 11,
    }
    return map[m] ?? null
  }

  function parsePeriodFromText(text: string): StatementPeriod | null {
    const re = /(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s*-\s*(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})/
    const m = text.match(re)
    if (!m) return null
    const d1 = Number(m[1])
    const mo1 = monthIndexFromAbbrev(m[2])
    const y1 = Number(m[3])
    const d2 = Number(m[4])
    const mo2 = monthIndexFromAbbrev(m[5])
    const y2 = Number(m[6])
    if (mo1 == null || mo2 == null) return null
    if (!Number.isFinite(d1) || !Number.isFinite(y1) || !Number.isFinite(d2) || !Number.isFinite(y2)) return null
    const start = new Date(y1, mo1, d1)
    const end = new Date(y2, mo2, d2)
    if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime())) return null
    return { start, end }
  }

  function inferIsoDateFromDayMonth(input: string): string | null {
    const m = input.trim().match(/^(\d{1,2})\s+([A-Za-z]{3})(?:\s+(\d{2,4}))?$/)
    if (!m) return null
    const day = Number(m[1])
    const mo = monthIndexFromAbbrev(m[2])
    const yRaw = m[3] ? Number(m[3]) : null
    if (!Number.isFinite(day) || mo == null) return null
    if (yRaw != null && Number.isFinite(yRaw)) {
      const y = yRaw < 100 ? 2000 + yRaw : yRaw
      const d = new Date(y, mo, day)
      if (!Number.isFinite(d.getTime())) return null
      return d.toISOString().slice(0, 10)
    }
    if (!period) return null
    const start = new Date(period.start)
    const end = new Date(period.end)
    start.setHours(0, 0, 0, 0)
    end.setHours(23, 59, 59, 999)
    const candidates = [period.start.getFullYear(), period.end.getFullYear(), period.start.getFullYear() + 1]
    for (const y of candidates) {
      const d = new Date(y, mo, day)
      if (d.getTime() >= start.getTime() && d.getTime() <= end.getTime()) {
        return d.toISOString().slice(0, 10)
      }
    }
    const fallback = new Date(period.start.getFullYear(), mo, day)
    if (!Number.isFinite(fallback.getTime())) return null
    return fallback.toISOString().slice(0, 10)
  }

  function isLikelyMoney(input: string): boolean {
    const s = input.trim()
    if (!s) return false
    if (/[€£$]/.test(s)) return true
    if (/\(\s*[-−+]?\d/.test(s) && /\)/.test(s)) return true
    if (/[-−+]/.test(s) && /[.,]\d{2}\b/.test(s)) return true
    if (/[.,]\d{2}\b/.test(s)) return true
    return false
  }

  function asIsoDate(input: string): string | null {
    const dm = inferIsoDateFromDayMonth(input)
    if (dm) return dm
    const d = parseDate(input)
    if (!d) return null
    return d.toISOString().slice(0, 10)
  }

  function normalizeHeaderToken(input: string): string {
    let s = String(input || '').trim().toLowerCase()
    if (!s) return ''
    const map: Record<string, string> = {
      ą: 'a',
      č: 'c',
      ę: 'e',
      ė: 'e',
      į: 'i',
      š: 's',
      ų: 'u',
      ū: 'u',
      ž: 'z',
    }
    s = s.replace(/[ąčęėįšųūž]/g, (m) => map[m] ?? m)
    s = s.replace(/\s+/g, ' ')
    return s
  }

  function headerHasAny(s: string, needles: string[]): boolean {
    for (const n of needles) if (s.includes(n)) return true
    return false
  }

  function buildTransactionsCsvFromMappedRows(mappedRows: string[][]): string[][] {
    const rows = mappedRows.filter((r) => r.some((c) => c.trim().length > 0))
    if (rows.length === 0) return []
    const width = Math.max(...rows.map((r) => r.length))
    const sample = rows.slice(0, 250)

    const scores = Array.from({ length: width }, () => ({ date: 0, money: 0, text: 0 }))
    for (const r of sample) {
      for (let i = 0; i < width; i++) {
        const v = (r[i] ?? '').trim()
        if (!v) continue
        if (asIsoDate(v)) scores[i]!.date += 1
        if (isLikelyMoney(v) && parseDecimal(v) != null) scores[i]!.money += 1
        if (/[A-Za-z]/.test(v) && v.length >= 3) scores[i]!.text += 1
      }
    }

    const pickBest = (key: 'date' | 'money' | 'text', exclude: Set<number>) => {
      let best = -1
      let bestScore = -1
      for (let i = 0; i < width; i++) {
        if (exclude.has(i)) continue
        const sc = scores[i]![key]
        if (sc > bestScore) {
          bestScore = sc
          best = i
        }
      }
      return bestScore > 0 ? best : -1
    }

    const used = new Set<number>()
    const dateCol = pickBest('date', used)
    if (dateCol >= 0) used.add(dateCol)

    const moneyColsAll: number[] = []
    for (let i = 0; i < width; i++) {
      if (scores[i]!.money > 0) moneyColsAll.push(i)
    }

    const descCol = pickBest('text', used)

    if (dateCol < 0 || descCol < 0) return []
    if (moneyColsAll.length === 0) return []

    const moneyStats = new Map<number, { fill: number; count: number }>()
    for (const i of moneyColsAll) moneyStats.set(i, { fill: 0, count: 0 })

    for (const r of rows) {
      for (const i of moneyColsAll) {
        const v = (r[i] ?? '').trim()
        if (!v) continue
        const n = parseDecimal(v)
        if (n == null) continue
        const s = moneyStats.get(i)
        if (!s) continue
        s.count += 1
      }
    }

    for (const i of moneyColsAll) {
      const s = moneyStats.get(i)!
      s.fill = rows.length ? s.count / rows.length : 0
    }

    let balCol = -1
    if (moneyColsAll.length >= 2) {
      let bestFill = -1
      let bestIdx = -1
      for (const i of moneyColsAll) {
        const f = moneyStats.get(i)!.fill
        if (f > bestFill || (f === bestFill && i > bestIdx)) {
          bestFill = f
          bestIdx = i
        }
      }
      if (bestFill >= 0.6) balCol = bestIdx
    }

    type Entry = {
      dateIso: string
      dateObj: Date
      desc: string
      byCol: Map<number, string>
      bal: number | null
      balRaw: string
    }

    const entries: Entry[] = []
    for (const r of rows) {
      const dateRaw = (r[dateCol] ?? '').trim()
      const descRaw = (r[descCol] ?? '').trim()
      const iso = dateRaw ? asIsoDate(dateRaw) : null
      if (!iso) continue
      const d = new Date(iso + 'T00:00:00Z')
      if (!Number.isFinite(d.getTime())) continue
      const byCol = new Map<number, string>()
      for (const i of moneyColsAll) {
        const v = (r[i] ?? '').trim()
        if (v) byCol.set(i, v)
      }
      const balRaw = balCol >= 0 ? (r[balCol] ?? '').trim() : ''
      const bal = balCol >= 0 ? (parseDecimal(balRaw) ?? null) : null
      entries.push({ dateIso: iso, dateObj: d, desc: descRaw, byCol, bal, balRaw })
    }

    if (entries.length === 0) return []

    entries.sort((a, b) => a.dateObj.getTime() - b.dateObj.getTime())

    const tol = 0.05
    const debitScore = new Map<number, number>()
    const creditScore = new Map<number, number>()
    for (const i of moneyColsAll) {
      if (i === balCol) continue
      debitScore.set(i, 0)
      creditScore.set(i, 0)
    }

    if (balCol >= 0) {
      for (let i = 1; i < entries.length; i++) {
        const prev = entries[i - 1]!
        const cur = entries[i]!
        if (prev.bal == null || cur.bal == null) continue
        const delta = cur.bal - prev.bal
        if (Math.abs(delta) < tol) continue
        for (const col of moneyColsAll) {
          if (col === balCol) continue
          const raw = cur.byCol.get(col) ?? ''
          const n = raw ? parseDecimal(raw) : null
          if (n == null) continue
          const v = Math.abs(n)
          if (delta < 0) {
            if (Math.abs(v - Math.abs(delta)) <= tol) {
              debitScore.set(col, (debitScore.get(col) ?? 0) + 1)
            }
          } else if (delta > 0) {
            if (Math.abs(v - Math.abs(delta)) <= tol) {
              creditScore.set(col, (creditScore.get(col) ?? 0) + 1)
            }
          }
        }
      }
    }

    const remaining = moneyColsAll.filter((c) => c !== balCol)

    const pickBestCol = (m: Map<number, number>, exclude: Set<number>) => {
      let best = -1
      let bestScore = -1
      for (const [k, v] of m.entries()) {
        if (exclude.has(k)) continue
        if (v > bestScore) {
          bestScore = v
          best = k
        }
      }
      return bestScore > 0 ? best : -1
    }

    const usedMoney = new Set<number>()
    let outCol = pickBestCol(debitScore, usedMoney)
    if (outCol >= 0) usedMoney.add(outCol)
    let inCol = pickBestCol(creditScore, usedMoney)
    if (inCol >= 0) usedMoney.add(inCol)

    if (outCol < 0 && inCol < 0) {
      const sorted = remaining
        .map((c) => ({ c, fill: moneyStats.get(c)!.fill }))
        .sort((a, b) => a.fill - b.fill || a.c - b.c)
        .map((x) => x.c)
      outCol = sorted[0] ?? -1
      inCol = sorted[1] ?? -1
    } else if (outCol < 0 && remaining.length > 0) {
      outCol = remaining[0]!
      if (outCol === inCol) outCol = remaining.find((c) => c !== inCol) ?? outCol
    } else if (inCol < 0 && remaining.length > 0) {
      inCol = remaining.find((c) => c !== outCol) ?? -1
    }

    if (outCol < 0) return []

    const out: string[][] = [['Date', 'Description', 'Notes', 'Money out', 'Money in', 'Balance']]

    const balanceByDate = new Map<string, number>()
    if (balCol >= 0) {
      for (const e of entries) {
        if (e.bal != null) balanceByDate.set(e.dateIso + '|' + e.desc, e.bal)
      }
    }

    for (let i = 0; i < entries.length; i++) {
      const e = entries[i]!
      const prev = i > 0 ? entries[i - 1]! : null
      const delta = prev?.bal != null && e.bal != null ? e.bal - prev.bal : null

      const outRaw = outCol >= 0 ? (e.byCol.get(outCol) ?? '').trim() : ''
      const inRaw = inCol >= 0 ? (e.byCol.get(inCol) ?? '').trim() : ''
      const balRaw = e.balRaw

      let moneyOut = ''
      let moneyIn = ''

      const nOut = outRaw ? parseDecimal(outRaw) : null
      const nIn = inRaw ? parseDecimal(inRaw) : null

      if (inCol >= 0 && (nOut != null || nIn != null)) {
        if (nOut != null && nOut !== 0) moneyOut = String(Math.abs(nOut))
        if (nIn != null && nIn !== 0) moneyIn = String(Math.abs(nIn))
        if (!moneyOut && !moneyIn && delta != null) {
          const v = nOut != null ? Math.abs(nOut) : nIn != null ? Math.abs(nIn) : 0
          if (v) {
            if (delta < 0) moneyOut = String(v)
            else if (delta > 0) moneyIn = String(v)
          }
        }
      } else {
        const n = nOut
        if (n == null || n === 0) continue
        const v = Math.abs(n)
        if (delta != null) {
          if (delta < 0) moneyOut = String(v)
          else if (delta > 0) moneyIn = String(v)
          else continue
        } else if (n < 0) {
          moneyOut = String(v)
        } else {
          moneyIn = String(v)
        }
      }

      if (!moneyOut && !moneyIn) continue

      const first = e.desc || 'Transaction'
      out.push([e.dateIso, first, '', moneyOut, moneyIn, balRaw])
    }

    return out.length > 1 ? out : []
  }

  let csvRows: string[][] = []
  let barclaysHeaderAdded = false

  for (let p = 1; p <= doc.numPages; p++) {
    const page = await doc.getPage(p)
    const content = await page.getTextContent()
    
    // Filter and normalize items
    const items = (content.items as PdfTextItem[]).filter(it => it.str.trim().length > 0)
    if (items.length === 0) continue

    if (!period) {
      const pageText = items.map((it) => it.str).join(' ')
      const found = parsePeriodFromText(pageText)
      if (found) period = found
    }

    // Group items by Y coordinate (rounded to nearest 4 pixels to account for slight misalignment)
    // In PDF coordinates, Y = transform[5]. We sort descending because Y increases upwards.
    items.sort((a, b) => b.transform[5] - a.transform[5])
    
    const rows: PdfTextItem[][] = []
    let currentRow: PdfTextItem[] = []
    let currentY = items[0].transform[5]

    for (const item of items) {
      if (Math.abs(item.transform[5] - currentY) <= 4) {
        currentRow.push(item)
      } else {
        rows.push(currentRow)
        currentRow = [item]
        currentY = item.transform[5]
      }
    }
    if (currentRow.length > 0) rows.push(currentRow)

    // Collect all X coordinates across the page to determine columns
    const xs = items.map(it => it.transform[4]).sort((a, b) => a - b)
    const columns: number[] = []
    let currentCluster: number[] = []
    const xTolerance = 15 // pixels

    for (const x of xs) {
      if (currentCluster.length === 0) {
        currentCluster.push(x)
      } else {
        const avg = currentCluster.reduce((a, b) => a + b, 0) / currentCluster.length
        if (Math.abs(x - avg) <= xTolerance) {
          currentCluster.push(x)
        } else {
          columns.push(currentCluster.reduce((a, b) => a + b, 0) / currentCluster.length)
          currentCluster = [x]
        }
      }
    }
    if (currentCluster.length > 0) {
      columns.push(currentCluster.reduce((a, b) => a + b, 0) / currentCluster.length)
    }

    const mappedRows: string[][] = []
    // Now for each row, map items to columns
    for (const rowItems of rows) {
      const rowStrings = new Array(columns.length).fill('')
      
      for (const item of rowItems) {
        const x = item.transform[4]
        // Find closest column
        let closestIdx = 0
        let minDiff = Infinity
        for (let i = 0; i < columns.length; i++) {
          const diff = Math.abs(x - columns[i])
          if (diff < minDiff) {
            minDiff = diff
            closestIdx = i
          }
        }
        
        // Append text if column already has text
        if (rowStrings[closestIdx]) {
          rowStrings[closestIdx] += ' ' + item.str.trim()
        } else {
          rowStrings[closestIdx] = item.str.trim()
        }
      }
      
      // Trim all columns and filter out completely empty rows
      const trimmed = rowStrings.map(s => s.trim())
      if (trimmed.some(s => s.length > 0)) {
        mappedRows.push(trimmed)
      }
    }

    const headerRowIndex = mappedRows.findIndex((r) => {
      const s = normalizeHeaderToken(r.join(' '))
      const hasDate = headerHasAny(s, ['date', 'transaction date', 'posted date', 'data', 'operacijos data'])
      const hasDesc = headerHasAny(s, ['description', 'details', 'merchant', 'name', 'payee', 'aprasymas', 'pavadinimas', 'mokejimo paskirtis', 'paskirtis'])
      const hasOut = headerHasAny(s, ['money out', 'paid out', 'debit', 'issiusti pinigai', 'issiusti', 'is siusti'])
      const hasIn = headerHasAny(s, ['money in', 'paid in', 'credit', 'gauti pinigai', 'gauti'])
      return hasDate && hasDesc && (hasOut || hasIn)
    })

    if (headerRowIndex >= 0) {
      const header = mappedRows[headerRowIndex]
      const norm = (x: string) => normalizeHeaderToken(x)
      const dateCol = header.findIndex((c) => headerHasAny(norm(c), ['date', 'data', 'operacijos data']))
      const descCol = header.findIndex((c) =>
        headerHasAny(norm(c), ['description', 'details', 'merchant', 'name', 'payee', 'aprasymas', 'pavadinimas', 'mokejimo paskirtis', 'paskirtis']),
      )
      const outCol = header.findIndex((c) => headerHasAny(norm(c), ['money out', 'paid out', 'debit', 'issiusti pinigai', 'issiusti', 'is siusti']))
      const inCol = header.findIndex((c) => headerHasAny(norm(c), ['money in', 'paid in', 'credit', 'gauti pinigai', 'gauti']))
      const balCol = header.findIndex((c) => headerHasAny(norm(c), ['balance', 'likutis', 'balansas']))

      const hasTwoMoneyCols = dateCol >= 0 && descCol >= 0 && outCol >= 0 && inCol >= 0
      const hasBarclaysCols = dateCol >= 0 && descCol >= 0 && outCol >= 0 && inCol >= 0 && balCol >= 0

      if (hasTwoMoneyCols) {
        if (!barclaysHeaderAdded) {
          csvRows.push(['Date', 'Description', 'Notes', 'Money out', 'Money in', 'Balance'])
          barclaysHeaderAdded = true
        }

        const scan = mappedRows.slice(headerRowIndex + 1, headerRowIndex + 1 + 150)
        const isNumericCell = (v: string) => parseDecimal(v) != null
        const bestNumericNear = (center: number, forbidden: Set<number>) => {
          const start = Math.max(0, center - 3)
          const end = Math.min((mappedRows[0]?.length ?? center + 4), center + 4)
          let best = center
          let bestScore = -1
          let bestDist = Number.POSITIVE_INFINITY
          for (let i = start; i < end; i++) {
            if (forbidden.has(i)) continue
            let score = 0
            for (const r of scan) if (isNumericCell(r[i] ?? '')) score += 1
            const dist = Math.abs(i - center)
            if (score > bestScore || (score === bestScore && dist < bestDist)) {
              bestScore = score
              best = i
              bestDist = dist
            }
          }
          return best
        }
        const bestTextCol = (from: number, to: number) => {
          const start = Math.max(0, from)
          const end = Math.min(mappedRows[0]?.length ?? to, to)
          let best = start
          let bestScore = -1
          for (let i = start; i < end; i++) {
            let score = 0
            for (const r of scan) if ((r[i] ?? '').trim()) score += 1
            if (score > bestScore) {
              bestScore = score
              best = i
            }
          }
          return best
        }

        const forbiddenMoney = new Set<number>()
        if (balCol >= 0) forbiddenMoney.add(balCol)

        const outColActual = bestNumericNear(outCol, forbiddenMoney)
        const inColActual = bestNumericNear(inCol, forbiddenMoney)

        const stopTextAt = Math.min(outColActual, inColActual)
        const descColActual = bestTextCol(descCol, stopTextAt)

        const betweenDescAndStop = (r: string[]) => {
          const stop = stopTextAt === Infinity ? r.length : stopTextAt
          const slice = r
            .slice(descColActual, stop)
            .map((x) => x.trim())
            .filter((x) => x.length > 0)
          return slice.join(' ').trim()
        }

        for (const r of mappedRows.slice(headerRowIndex + 1)) {
          const dateRaw = (r[dateCol] ?? '').trim()
          const dateIso = dateRaw ? asIsoDate(dateRaw) : null
          if (!dateIso) continue

          const outRaw = (r[outColActual] ?? '').trim()
          const inRaw = (r[inColActual] ?? '').trim()
          const balRaw = ''
          const descRaw = betweenDescAndStop(r)

          const nOut = parseDecimal(outRaw)
          const nIn = parseDecimal(inRaw)
          const hasAmount = (nOut != null && nOut !== 0) || (nIn != null && nIn !== 0)
          if (!hasAmount) continue

          const moneyOut = nOut != null && nOut !== 0 ? String(Math.abs(nOut)) : ''
          const moneyIn = nIn != null && nIn !== 0 ? String(Math.abs(nIn)) : ''
          const first = descRaw || 'Transaction'
          csvRows.push([dateIso, first, '', moneyOut, moneyIn, balRaw])
        }
        continue
      }

      if (hasBarclaysCols) {
        continue
      }
    }

    const generic = buildTransactionsCsvFromMappedRows(mappedRows)
    if (generic.length > 0) {
      csvRows.push(...generic)
    } else {
      csvRows.push(...mappedRows)
    }
  }

  // Convert array of arrays to CSV string
  return csvRows.map(row => 
    row.map(cell => `"${cell.replace(/"/g, '""')}"`).join(',')
  ).join('\n')
}

export async function parsePdfRows(file: File): Promise<CsvRow[]> {
  const csvString = await convertPdfToCsvString(file)
  return parseCsvRows(csvString)
}

export function pdfRowsToTransactions(
  rows: CsvRow[],
  fallbackCurrencyCode: string,
  accountIdResolver: (rawAccount: string | undefined) => UUID | null,
): Transaction[] {
  // Use the exact same logic as CSV since we converted PDF to CSV!
  const txs = rowsToTransactions(rows, fallbackCurrencyCode, accountIdResolver)
  // Just update the tag to be bank-pdf
  for (const t of txs) {
    t.tags = ['bank-pdf']
  }
  return txs
}
