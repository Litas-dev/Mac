import { useMemo, useRef, useState } from 'react'
import { useAppStore } from '../../app/appStore'
import type { BillCategory, Transaction, TransactionKind, UUID } from '../../domain/models'
import { currency } from '../../domain/finance'
import { fromDateInputValue, toDateInputValue } from '../date'
import { parseCsvRows, rowsToTransactions } from '../../domain/csvImport'
import { parsePdfRows, pdfRowsToTransactions, convertPdfToCsvString } from '../../domain/pdfImport'
import { useContextMenu } from '../ContextMenu'
import { MenuSelect } from '../MenuSelect'
import { TransactionKindIcon } from '../icons'
import { isTauriRuntime } from '../../storage/tauriJsonStore'
import { invoke } from '@tauri-apps/api/core'
import { save } from '@tauri-apps/plugin-dialog'

export function TransactionsView() {
  const { state, dispatch } = useAppStore()
  const selectedId = state.ui.selectedTransactionId
  const [search, setSearch] = useState('')
  const [accountFilterId, setAccountFilterId] = useState<UUID | 'all'>('all')
  const [kindFilter, setKindFilter] = useState<TransactionKind | 'all'>('all')
  const [sourceFilter, setSourceFilter] = useState<'all' | 'imported' | 'manual'>('all')
  const [dateFilter, setDateFilter] = useState<'all' | 'last30' | 'last90' | 'thisMonth' | 'range'>('all')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [payeeFilter, setPayeeFilter] = useState<string | 'all'>('all')
  const [categoryFilter, setCategoryFilter] = useState<BillCategory | 'all'>('all')
  const [sort, setSort] = useState<'dateDesc' | 'dateAsc' | 'amountDesc' | 'amountAsc' | 'netDesc' | 'netAsc'>('dateDesc')
  const [showEditor, setShowEditor] = useState(true)
  const [selectedIds, setSelectedIds] = useState<Set<UUID>>(() => new Set())
  const [taxRatePct, setTaxRatePct] = useState<number>(0)
  const [taxBase, setTaxBase] = useState<'income' | 'expense' | 'net'>('income')
  const [taxOverrideEnabled, setTaxOverrideEnabled] = useState(false)
  const [taxOverrideAmount, setTaxOverrideAmount] = useState<number>(0)
  const [importingPdf, setImportingPdf] = useState(false)
  const [convertingPdf, setConvertingPdf] = useState(false)
  const fileInputRef = useRef<HTMLInputElement | null>(null)
  const pdfInputRef = useRef<HTMLInputElement | null>(null)
  const convertPdfInputRef = useRef<HTMLInputElement | null>(null)
  const enableTaxPdf = import.meta.env.DEV || import.meta.env.VITE_ENABLE_TAX_PDF === '1'

  function payeeGroupKey(raw: string | null | undefined): string {
    const s = (raw ?? '').trim()
    if (!s) return ''
    const parts = s.split(',').map((x) => x.trim()).filter((x) => x.length > 0)
    const head = parts[0] ?? s
    const cleaned = head.replace(/\s+/g, ' ').trim()
    return cleaned.toUpperCase()
  }

  function shiftDateValue(value: string, deltaYears: number, deltaMonths: number): string {
    const base = value ? fromDateInputValue(value) : new Date()
    const nextMonthAnchor = new Date(base.getFullYear() + deltaYears, base.getMonth() + deltaMonths, 1)
    const lastDay = new Date(nextMonthAnchor.getFullYear(), nextMonthAnchor.getMonth() + 1, 0).getDate()
    const day = Math.min(base.getDate(), lastDay)
    return toDateInputValue(new Date(nextMonthAnchor.getFullYear(), nextMonthAnchor.getMonth(), day))
  }

  const payeeGroups = useMemo(() => {
    const counts = new Map<string, number>()
    for (const t of state.transactions) {
      const k = payeeGroupKey(t.payee)
      if (!k) continue
      counts.set(k, (counts.get(k) ?? 0) + 1)
    }
    const rows = [...counts.entries()]
      .map(([key, count]) => ({ key, count }))
      .sort((a, b) => (b.count !== a.count ? b.count - a.count : a.key.localeCompare(b.key)))
      .slice(0, 60)
    return rows
  }, [state.transactions])

  const filtered = useMemo(() => {
    let items = state.transactions
    if (accountFilterId !== 'all') {
      items = items.filter((t) => t.accountId === accountFilterId || t.toAccountId === accountFilterId)
    }
    const q = search.trim().toLowerCase()
    if (q) {
      items = items.filter((t) => {
        const hay = [
          t.payee ?? '',
          t.notes ?? '',
          t.customCategoryName ?? '',
          ...(t.tags ?? []),
        ]
          .join(' ')
          .toLowerCase()
        return hay.includes(q)
      })
    }
    if (kindFilter !== 'all') items = items.filter((t) => t.kind === kindFilter)
    if (sourceFilter !== 'all') {
      const isImported = (t: Transaction) => (t.tags ?? []).includes('bank-csv') || (t.tags ?? []).includes('bank-pdf')
      if (sourceFilter === 'imported') items = items.filter(isImported)
      if (sourceFilter === 'manual') items = items.filter((t) => !isImported(t))
    }
    if (payeeFilter !== 'all') {
      items = items.filter((t) => payeeGroupKey(t.payee) === payeeFilter)
    }
    if (categoryFilter !== 'all') {
      items = items.filter((t) => t.kind === 'expense' && t.category === categoryFilter)
    }
    if (dateFilter !== 'all') {
      const now = new Date()
      if (dateFilter === 'last30') {
        const past = new Date(now)
        past.setDate(past.getDate() - 30)
        items = items.filter((t) => t.date >= past)
      } else if (dateFilter === 'last90') {
        const past = new Date(now)
        past.setDate(past.getDate() - 90)
        items = items.filter((t) => t.date >= past)
      } else if (dateFilter === 'thisMonth') {
        items = items.filter((t) => t.date.getFullYear() === now.getFullYear() && t.date.getMonth() === now.getMonth())
      } else if (dateFilter === 'range') {
        const from = dateFrom ? fromDateInputValue(dateFrom) : null
        const to = dateTo ? fromDateInputValue(dateTo) : null
        const toExclusive = to
          ? (() => {
              const d = new Date(to)
              d.setDate(d.getDate() + 1)
              return d
            })()
          : null
        items = items.filter((t) => {
          if (from && t.date < from) return false
          if (toExclusive && t.date >= toExclusive) return false
          return true
        })
      }
    }
    const signedValue = (t: Transaction): number => {
      if (t.kind === 'income') return t.amount.value
      if (t.kind === 'expense') return -t.amount.value
      return 0
    }
    const signedAmount = (t: Transaction): number => {
      if (t.kind === 'income') return t.amount.value
      if (t.kind === 'expense') return -t.amount.value
      return t.amount.value
    }
    switch (sort) {
      case 'dateDesc':
        return [...items].sort((a, b) => b.date.getTime() - a.date.getTime())
      case 'dateAsc':
        return [...items].sort((a, b) => a.date.getTime() - b.date.getTime())
      case 'amountDesc':
        return [...items].sort((a, b) => b.amount.value - a.amount.value)
      case 'amountAsc':
        return [...items].sort((a, b) => a.amount.value - b.amount.value)
      case 'netDesc':
        return [...items].sort((a, b) => signedValue(b) - signedValue(a))
      case 'netAsc':
        return [...items].sort((a, b) => signedValue(a) - signedValue(b))
      default:
        return [...items].sort((a, b) => signedAmount(b) - signedAmount(a))
    }
  }, [accountFilterId, dateFilter, dateFrom, dateTo, kindFilter, payeeFilter, search, sort, sourceFilter, state.transactions])

  const selected = useMemo(() => {
    if (!selectedId) return null
    return state.transactions.find((t) => t.id === selectedId) ?? null
  }, [selectedId, state.transactions])

  const selectedTx = useMemo(() => {
    if (selectedIds.size === 0) return []
    const byId = new Map<string, Transaction>()
    for (const t of state.transactions) byId.set(t.id, t)
    const out: Transaction[] = []
    for (const id of selectedIds) {
      const t = byId.get(id)
      if (t) out.push(t)
    }
    out.sort((a, b) => a.date.getTime() - b.date.getTime())
    return out
  }, [selectedIds, state.transactions])

  const selectionTotals = useMemo(() => {
    let income = 0
    let expense = 0
    for (const t of selectedTx) {
      if (t.kind === 'income') income += t.amount.value
      else if (t.kind === 'expense') expense += t.amount.value
    }
    const net = income - expense
    const base = taxBase === 'income' ? income : taxBase === 'expense' ? expense : net
    const rate = Number.isFinite(taxRatePct) ? taxRatePct : 0
    const computedTax = Math.max(0, base) * (rate / 100)
    const tax = taxOverrideEnabled ? Math.max(0, taxOverrideAmount || 0) : computedTax
    const totalWithTax = base + tax
    return { income, expense, net, base, computedTax, tax, totalWithTax }
  }, [selectedTx, taxBase, taxOverrideAmount, taxOverrideEnabled, taxRatePct])

  function createTransaction() {
    const defaultAccount = state.accounts.find((a) => !a.archived)?.id ?? null
    const t: Transaction = {
      id: crypto.randomUUID(),
      kind: 'expense',
      date: new Date(),
      amount: { currencyCode: state.settings.displayCurrencyCode, value: 0 },
      accountId: defaultAccount,
      toAccountId: null,
      category: 'other',
      customCategoryName: null,
      payee: null,
      notes: null,
      tags: [],
      relatedBillId: null,
      relatedIncomeId: null,
    }
    dispatch({ type: 'transactions/add', transaction: t })
  }

  function deleteSelected() {
    if (!selected) return
    if (!window.confirm('Delete transaction?')) return
    dispatch({ type: 'transactions/delete', id: selected.id })
  }

  function updateSelected(patch: Partial<Transaction>) {
    if (!selected) return
    let next: Transaction = { ...selected, ...patch }
    if (next.kind !== 'transfer') next = { ...next, toAccountId: null }
    if (next.kind !== 'expense') next = { ...next, category: null, customCategoryName: null }
    dispatch({ type: 'transactions/update', transaction: next })
  }

  function toggleSelection(id: UUID) {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  function clearSelection() {
    setSelectedIds(new Set())
  }

  function selectAllFiltered() {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      for (const t of filtered) next.add(t.id)
      return next
    })
  }

  async function printSelection() {
    if (selectedTx.length === 0) return
    if (!enableTaxPdf) return
    const displayCurrency = state.settings.displayCurrencyCode
    const fmt = (n: number) => currency(n, displayCurrency)
    const baseLabel = taxBase === 'income' ? 'Income' : taxBase === 'expense' ? 'Expenses' : 'Net'

    const [{ default: JsPDF }, { default: autoTable }] = await Promise.all([import('jspdf'), import('jspdf-autotable')])
    const doc = new JsPDF({ unit: 'pt', format: 'a4' })
    const pageWidth = doc.internal.pageSize.getWidth()
    
    doc.setFontSize(18)
    doc.text('Selected Transactions', 42, 48)
    
    doc.setFontSize(10)
    doc.setTextColor(100, 100, 100)
    doc.text(`Count: ${selectedTx.length}`, 42, 64)
    
    doc.setDrawColor(200, 200, 200)
    doc.setFillColor(250, 250, 250)
    doc.roundedRect(42, 76, pageWidth - 84, 62, 6, 6, 'FD')
    
    doc.setFontSize(11)
    doc.setTextColor(0, 0, 0)
    
    const col1X = 56
    const val1X = 206
    const col2X = 270
    const val2X = 420
    
    doc.setFont('helvetica', 'normal')
    doc.text('Income:', col1X, 98)
    doc.text('Expenses:', col1X, 116)
    doc.text('Net:', col1X, 134)
    
    doc.setFont('helvetica', 'bold')
    doc.text(fmt(selectionTotals.income), val1X, 98, { align: 'right' })
    doc.text(fmt(selectionTotals.expense), val1X, 116, { align: 'right' })
    doc.text(fmt(selectionTotals.net), val1X, 134, { align: 'right' })
    
    doc.setFont('helvetica', 'normal')
    doc.text(`Tax base (${baseLabel}):`, col2X, 98)
    doc.text('Tax:', col2X, 116)
    doc.text('Total + Tax:', col2X, 134)
    
    doc.setFont('helvetica', 'bold')
    doc.text(fmt(selectionTotals.base), val2X, 98, { align: 'right' })
    doc.text(fmt(selectionTotals.tax), val2X, 116, { align: 'right' })
    doc.text(fmt(selectionTotals.totalWithTax), val2X, 134, { align: 'right' })

    const tableData = selectedTx.map((t) => {
      const account = t.accountId ? accountNameById.get(t.accountId) ?? '' : ''
      const amt = t.kind === 'expense' ? -t.amount.value : t.amount.value
      return [
        toDateInputValue(t.date),
        t.payee ?? '',
        account,
        fmt(amt),
        t.notes ?? ''
      ]
    })

    autoTable(doc, {
      startY: 156,
      head: [['Date', 'Payee', 'Account', 'Amount', 'Notes']],
      body: tableData,
      theme: 'striped',
      headStyles: { fillColor: [66, 66, 66] },
      columnStyles: {
        3: { halign: 'right' }
      },
      styles: { fontSize: 9 },
      didDrawPage: () => {
        const pageNumber = doc.getNumberOfPages()
        doc.setFontSize(9)
        doc.setTextColor(120, 120, 120)
        doc.text(`Kivana • ${new Date().toLocaleString()} • Page ${pageNumber}`, 42, doc.internal.pageSize.getHeight() - 28)
        doc.setTextColor(0, 0, 0)
      }
    })

    if (isTauriRuntime()) {
      const defaultFileName = `transactions-summary-${new Date().toISOString().slice(0, 10)}.pdf`
      const filePath = await save({
        filters: [{ name: 'PDF', extensions: ['pdf'] }],
        defaultPath: defaultFileName,
      })
      
      if (!filePath) return // user cancelled
      
      try {
        const pdfArrayBuffer = doc.output('arraybuffer')
        const pdfBytes = Array.from(new Uint8Array(pdfArrayBuffer))
        await invoke('export_pdf', { destinationPath: filePath, pdfContent: pdfBytes })
        window.alert('PDF saved successfully!')
      } catch (err) {
        console.error('Error saving PDF:', err)
        window.alert('Failed to save PDF: ' + String(err))
      }
    } else {
      // Fallback for browser testing
      doc.save(`transactions-summary-${new Date().toISOString().slice(0, 10)}.pdf`)
    }
  }

  function importCsvClick() {
    fileInputRef.current?.click()
  }

  function importPdfClick() {
    pdfInputRef.current?.click()
  }

  function convertPdfClick() {
    convertPdfInputRef.current?.click()
  }

  async function onPickCsv(file: File | null) {
    if (!file) return
    const text = await file.text()
    const rows = parseCsvRows(text)
    const activeAccounts = state.accounts.filter((a) => !a.archived)
    const resolveAccountId = (raw: string | undefined): UUID | null => {
      const normalized = (raw ?? '').trim()
      if (!normalized) return activeAccounts[0]?.id ?? null
      const exact = activeAccounts.find((a) => a.name.localeCompare(normalized, undefined, { sensitivity: 'accent' }) === 0)
      if (exact) return exact.id
      const contains = activeAccounts.find((a) => a.name.toLowerCase().includes(normalized.toLowerCase()) || (a.institution ?? '').toLowerCase().includes(normalized.toLowerCase()))
      return contains?.id ?? activeAccounts[0]?.id ?? null
    }
    const imported = rowsToTransactions(rows, state.settings.displayCurrencyCode, resolveAccountId)
    if (imported.length === 0) {
      window.alert('Import complete. No transactions were imported.')
      return
    }
    for (const t of imported) {
      dispatch({ type: 'transactions/add', transaction: t })
    }
    window.alert(`Import complete. Imported ${imported.length} transactions.`)
  }

  async function onPickPdf(file: File | null) {
    if (!file) return
    setImportingPdf(true)
    try {
      const rows = await parsePdfRows(file)
      const activeAccounts = state.accounts.filter((a) => !a.archived)
      const resolveAccountId = (raw: string | undefined): UUID | null => {
        const normalized = (raw ?? '').trim()
        if (!normalized) return activeAccounts[0]?.id ?? null
        const exact = activeAccounts.find((a) => a.name.localeCompare(normalized, undefined, { sensitivity: 'accent' }) === 0)
        if (exact) return exact.id
        const contains = activeAccounts.find((a) => a.name.toLowerCase().includes(normalized.toLowerCase()) || (a.institution ?? '').toLowerCase().includes(normalized.toLowerCase()))
        return contains?.id ?? activeAccounts[0]?.id ?? null
      }
      const imported = pdfRowsToTransactions(rows, state.settings.displayCurrencyCode, resolveAccountId)
      if (imported.length === 0) {
        window.alert('Import complete. No transactions could be identified in the PDF.')
        return
      }
      for (const t of imported) {
        dispatch({ type: 'transactions/add', transaction: t })
      }
      window.alert(`Import complete. Imported ${imported.length} transactions.`)
    } catch (e) {
      console.error(e)
      window.alert('Failed to parse PDF file. Ensure it is a valid bank statement PDF.')
    } finally {
      setImportingPdf(false)
    }
  }

  async function onConvertPdf(file: File | null) {
    if (!file) return
    setConvertingPdf(true)
    try {
      const csvString = await convertPdfToCsvString(file)
      const defaultName = file.name.replace(/\.pdf$/i, '.csv')
      if (isTauriRuntime()) {
        const { save } = await import('@tauri-apps/plugin-dialog')
        const { invoke } = await import('@tauri-apps/api/core')
        const path = await save({ defaultPath: defaultName })
        if (!path) return
        await invoke('export_csv', { destination_path: path, csv_content: csvString })
        window.alert('CSV saved.')
      } else {
        const blob = new Blob([csvString], { type: 'text/csv;charset=utf-8;' })
        const url = URL.createObjectURL(blob)
        const a = document.createElement('a')
        a.href = url
        a.download = defaultName
        a.click()
        URL.revokeObjectURL(url)
        window.alert('CSV downloaded.')
      }
    } catch (e) {
      console.error(e)
      window.alert('Failed to convert PDF file.')
    } finally {
      setConvertingPdf(false)
    }
  }

  const categories: BillCategory[] = ['housing', 'utilities', 'subscriptions', 'insurance', 'taxes', 'transport', 'other']
  const activeAccounts = useMemo(() => state.accounts.filter((a) => !a.archived).sort((a, b) => a.name.localeCompare(b.name)), [state.accounts])

  const accountNameById = useMemo(() => {
    const m = new Map<string, string>()
    for (const a of state.accounts) m.set(a.id, a.name)
    return m
  }, [state.accounts])

  const activeFilterCount = useMemo(() => {
    let c = 0
    if (accountFilterId !== 'all') c += 1
    if (kindFilter !== 'all') c += 1
    if (sourceFilter !== 'all') c += 1
    if (dateFilter !== 'all') {
      if (dateFilter !== 'range') c += 1
      else if (dateFrom || dateTo) c += 1
    }
    if (payeeFilter !== 'all') c += 1
    if (categoryFilter !== 'all') c += 1
    if (sort !== 'dateDesc') c += 1
    if (search.trim()) c += 1
    return c
  }, [accountFilterId, categoryFilter, dateFilter, dateFrom, dateTo, kindFilter, payeeFilter, search, sort, sourceFilter])

  const filterSummary = useMemo(() => {
    const parts: string[] = []
    if (accountFilterId !== 'all') {
      const name = accountNameById.get(accountFilterId) ?? 'Account'
      parts.push(`Acct: ${name}`)
    }
    if (kindFilter !== 'all') {
      parts.push(kindFilter === 'expense' ? 'Expenses' : kindFilter === 'income' ? 'Income' : 'Transfers')
    }
    if (sourceFilter !== 'all') parts.push(sourceFilter === 'imported' ? 'Imported' : 'Manual')
    if (dateFilter !== 'all') {
      if (dateFilter === 'range') {
        const from = dateFrom ? dateFrom : '…'
        const to = dateTo ? dateTo : 'now'
        parts.push(`Date: ${from} → ${to}`)
      } else {
        parts.push(dateFilter === 'last30' ? 'Last 30 days' : dateFilter === 'last90' ? 'Last 90 days' : 'This month')
      }
    }
    if (payeeFilter !== 'all') parts.push(`Payee: ${payeeFilter}`)
    if (categoryFilter !== 'all') parts.push(`Cat: ${categoryFilter}`)
    if (sort !== 'dateDesc') {
      const label =
        sort === 'dateAsc'
          ? 'Oldest'
          : sort === 'amountDesc'
            ? 'Amount ↓'
            : sort === 'amountAsc'
              ? 'Amount ↑'
              : sort === 'netDesc'
                ? 'Net ↓'
                : 'Net ↑'
      parts.push(`Sort: ${label}`)
    }
    return parts.join(' • ')
  }, [accountFilterId, accountNameById, categoryFilter, dateFilter, dateFrom, dateTo, kindFilter, payeeFilter, sort, sourceFilter])

  function clearFilters() {
    setAccountFilterId('all')
    setKindFilter('all')
    setSourceFilter('all')
    setDateFilter('all')
    setDateFrom('')
    setDateTo('')
    setPayeeFilter('all')
    setCategoryFilter('all')
    setSort('dateDesc')
  }

  function txnTitle(t: Transaction): string {
    if (t.payee && t.payee.trim()) return t.payee
    if (t.kind === 'income') return 'Income'
    if (t.kind === 'expense') return 'Expense'
    return 'Transfer'
  }

  function txnSubtitle(t: Transaction): string {
    const account = t.accountId ? accountNameById.get(t.accountId) : null
    const parts: string[] = []
    if (account) parts.push(account)
    if (t.kind === 'expense') {
      const cat = t.customCategoryName?.trim() || t.category
      if (cat) parts.push(String(cat))
    }
    if ((t.tags ?? []).includes('bank-csv') || (t.tags ?? []).includes('bank-pdf')) parts.push('Imported')
    return parts.join(' • ')
  }

  function signedAmount(t: Transaction): number {
    if (t.kind === 'expense') return -t.amount.value
    return t.amount.value
  }

  function amountTone(t: Transaction): 'pos' | 'neg' | 'neutral' {
    if (t.kind === 'income') return 'pos'
    if (t.kind === 'expense') return 'neg'
    return 'neutral'
  }

  function focusFirstEditorField() {
    window.setTimeout(() => {
      const el = document.querySelector('.detail .form input, .detail .form select, .detail .form textarea') as HTMLElement | null
      el?.focus?.()
    }, 0)
  }

  const rowMenu = useContextMenu([
    {
      id: 'edit',
      label: 'Edit',
      onSelect: () => {
        if (!selectedId) return
        dispatch({ type: 'ui/selectTransaction', id: selectedId })
        focusFirstEditorField()
      },
    },
    { id: 'sep', kind: 'separator' as const },
    {
      id: 'delete',
      label: 'Delete',
      tone: 'danger',
      onSelect: () => {
        if (!selectedId) return
        if (!window.confirm('Delete transaction?')) return
        dispatch({ type: 'transactions/delete', id: selectedId })
      },
    },
  ])

  return (
    <>
      <div className="toolbarWrap">
        <div className="row">
          <div className="toolbarLeft">
            <div className="toolbarSubtitle">
              {filtered.length.toLocaleString()} / {state.transactions.length.toLocaleString()} shown
              {filterSummary ? ` • ${filterSummary}` : ''}
            </div>
          </div>
          <div className="rowActions">
              <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search" style={{ width: 180 }} />
              <button type="button" onClick={importCsvClick}>
                Import CSV
              </button>
              <button type="button" onClick={importPdfClick} disabled={importingPdf || convertingPdf}>
                Import PDF
              </button>
              <button type="button" onClick={convertPdfClick} disabled={importingPdf || convertingPdf}>
                Convert PDF to CSV
              </button>
              <button type="button" onClick={() => setShowEditor((v) => !v)}>
                {showEditor ? 'Hide Editor' : 'Show Editor'}
              </button>
              <button type="button" onClick={createTransaction} className="btnPrimary">
                Add
              </button>
              <button type="button" onClick={deleteSelected} disabled={!selected} className="btnDanger">
                Delete
              </button>
              <input
                ref={fileInputRef}
                type="file"
                accept=".csv,text/csv,text/plain"
                style={{ display: 'none' }}
                onChange={(e) => {
                  const f = e.currentTarget.files?.[0] ?? null
                  e.currentTarget.value = ''
                  void onPickCsv(f)
                }}
              />
              <input
                ref={pdfInputRef}
                type="file"
                accept=".pdf,application/pdf"
                style={{ display: 'none' }}
                onChange={(e) => {
                  const f = e.currentTarget.files?.[0] ?? null
                  e.currentTarget.value = ''
                  void onPickPdf(f)
                }}
              />
              <input
                ref={convertPdfInputRef}
                type="file"
                accept=".pdf,application/pdf"
                style={{ display: 'none' }}
                onChange={(e) => {
                  const f = e.currentTarget.files?.[0] ?? null
                  e.currentTarget.value = ''
                  void onConvertPdf(f)
                }}
              />
            </div>
        </div>
        <div className="row" style={{ marginTop: 8 }}>
          <div className="rowActions" style={{ flexWrap: 'wrap' }}>
            <label className="field" style={{ margin: 0 }}>
              <div className="fieldLabel">Account</div>
              <MenuSelect
                value={accountFilterId}
                options={[
                  { value: 'all', label: 'All Accounts' },
                  ...activeAccounts.map((a) => ({ value: a.id as any, label: a.name })),
                ]}
                onChange={(v) => setAccountFilterId(v as any)}
                width={220}
              />
            </label>
            <label className="field" style={{ margin: 0 }}>
              <div className="fieldLabel">Type</div>
              <MenuSelect
                value={kindFilter}
                options={[
                  { value: 'all', label: 'All' },
                  { value: 'expense', label: 'Expenses' },
                  { value: 'income', label: 'Income' },
                  { value: 'transfer', label: 'Transfers' },
                ]}
                onChange={(v) => setKindFilter(v as any)}
                width={150}
              />
            </label>
            <label className="field" style={{ margin: 0 }}>
              <div className="fieldLabel">Source</div>
              <MenuSelect
                value={sourceFilter}
                options={[
                  { value: 'all', label: 'All' },
                  { value: 'imported', label: 'Imported' },
                  { value: 'manual', label: 'Manual' },
                ]}
                onChange={(v) => setSourceFilter(v as any)}
                width={150}
              />
            </label>
            <label className="field" style={{ margin: 0 }}>
              <div className="fieldLabel">Date</div>
              <MenuSelect
                value={dateFilter}
                options={[
                  { value: 'all', label: 'All time' },
                  { value: 'last30', label: 'Last 30 days' },
                  { value: 'last90', label: 'Last 90 days' },
                  { value: 'thisMonth', label: 'This month' },
                  { value: 'range', label: 'Custom range' },
                ]}
                onChange={(v) => setDateFilter(v as any)}
                width={160}
              />
            </label>
            {dateFilter === 'range' ? (
              <>
                <label className="field" style={{ margin: 0 }}>
                  <div className="fieldLabel">From</div>
                  <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                    <input
                      type="date"
                      value={dateFrom}
                      onChange={(e) => setDateFrom(e.target.value)}
                      style={{
                        appearance: 'none',
                        border: '1px solid var(--border)',
                        background: 'var(--surface)',
                        color: 'var(--text-h)',
                        padding: '8px 10px',
                        borderRadius: 8,
                        fontSize: 13,
                        height: 34,
                        width: 140,
                      }}
                    />
                    <div style={{ display: 'grid', gridAutoFlow: 'column', gap: 6 }}>
                      <button type="button" onClick={() => setDateFrom((v) => shiftDateValue(v, -1, 0))} style={{ padding: '4px 6px', fontSize: 11 }}>
                        -1y
                      </button>
                      <button type="button" onClick={() => setDateFrom((v) => shiftDateValue(v, 1, 0))} style={{ padding: '4px 6px', fontSize: 11 }}>
                        +1y
                      </button>
                      <button type="button" onClick={() => setDateFrom((v) => shiftDateValue(v, 0, -1))} style={{ padding: '4px 6px', fontSize: 11 }}>
                        -1m
                      </button>
                      <button type="button" onClick={() => setDateFrom((v) => shiftDateValue(v, 0, 1))} style={{ padding: '4px 6px', fontSize: 11 }}>
                        +1m
                      </button>
                      <button type="button" onClick={() => setDateFrom('')} style={{ padding: '4px 6px', fontSize: 11 }}>
                        Clear
                      </button>
                    </div>
                  </div>
                </label>
                <label className="field" style={{ margin: 0 }}>
                  <div className="fieldLabel">To</div>
                  <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                    <input
                      type="date"
                      value={dateTo}
                      onChange={(e) => setDateTo(e.target.value)}
                      style={{
                        appearance: 'none',
                        border: '1px solid var(--border)',
                        background: 'var(--surface)',
                        color: 'var(--text-h)',
                        padding: '8px 10px',
                        borderRadius: 8,
                        fontSize: 13,
                        height: 34,
                        width: 140,
                      }}
                    />
                    <div style={{ display: 'grid', gridAutoFlow: 'column', gap: 6 }}>
                      <button type="button" onClick={() => setDateTo((v) => shiftDateValue(v, -1, 0))} style={{ padding: '4px 6px', fontSize: 11 }}>
                        -1y
                      </button>
                      <button type="button" onClick={() => setDateTo((v) => shiftDateValue(v, 1, 0))} style={{ padding: '4px 6px', fontSize: 11 }}>
                        +1y
                      </button>
                      <button type="button" onClick={() => setDateTo((v) => shiftDateValue(v, 0, -1))} style={{ padding: '4px 6px', fontSize: 11 }}>
                        -1m
                      </button>
                      <button type="button" onClick={() => setDateTo((v) => shiftDateValue(v, 0, 1))} style={{ padding: '4px 6px', fontSize: 11 }}>
                        +1m
                      </button>
                      <button type="button" onClick={() => setDateTo(toDateInputValue(new Date()))} style={{ padding: '4px 6px', fontSize: 11 }}>
                        Today
                      </button>
                      <button type="button" onClick={() => setDateTo('')} style={{ padding: '4px 6px', fontSize: 11 }}>
                        Clear
                      </button>
                    </div>
                  </div>
                </label>
              </>
            ) : null}
            <label className="field" style={{ margin: 0 }}>
              <div className="fieldLabel">Payee</div>
              <MenuSelect
                value={payeeFilter as any}
                options={[
                  { value: 'all', label: 'All' },
                  ...payeeGroups.map((x) => ({ value: x.key as any, label: `${x.key} (${x.count})` })),
                ]}
                onChange={(v) => setPayeeFilter(v as any)}
                width={340}
              />
            </label>
            <label className="field" style={{ margin: 0 }}>
              <div className="fieldLabel">Category</div>
              <MenuSelect
                value={categoryFilter}
                options={[
                  { value: 'all', label: 'All' },
                  ...categories.map((c) => ({ value: c as any, label: c })),
                ]}
                onChange={(v) => setCategoryFilter(v as any)}
                width={170}
              />
            </label>
            <label className="field" style={{ margin: 0 }}>
              <div className="fieldLabel">Sort</div>
              <MenuSelect
                value={sort}
                options={[
                  { value: 'dateDesc', label: 'Newest' },
                  { value: 'dateAsc', label: 'Oldest' },
                  { value: 'amountDesc', label: 'Amount ↓' },
                  { value: 'amountAsc', label: 'Amount ↑' },
                  { value: 'netDesc', label: 'Net ↓' },
                  { value: 'netAsc', label: 'Net ↑' },
                ]}
                onChange={(v) => setSort(v as any)}
                width={150}
              />
            </label>
            <button type="button" onClick={clearFilters} disabled={activeFilterCount === 0}>
              Clear Filters
            </button>
            <button type="button" onClick={selectAllFiltered} disabled={filtered.length === 0}>
              Select all shown
            </button>
            {selectedIds.size > 0 ? (
              <>
                <button type="button" onClick={clearSelection}>
                  Clear selection ({selectedIds.size})
                </button>
        {enableTaxPdf ? (
          <button type="button" onClick={printSelection} className="btnPrimary">
            Print / Save PDF
          </button>
        ) : null}
              </>
            ) : null}
          </div>
        </div>
      </div>

      <div className={showEditor ? 'split' : 'split noDetail'}>
        <div className="list">
          {filtered.map((t) => (
            <div
              key={t.id}
              role="button"
              tabIndex={0}
              className={t.id === selectedId && selectedIds.size === 0 ? 'listItem active txnRow' : 'listItem txnRow'}
              style={selectedIds.has(t.id) ? { background: 'var(--accent-bg-strong)' } : {}}
              onClick={() => {
                if (selectedIds.size > 0) {
                  toggleSelection(t.id)
                } else {
                  dispatch({ type: 'ui/selectTransaction', id: t.id })
                }
              }}
              onContextMenu={(e) => {
                dispatch({ type: 'ui/selectTransaction', id: t.id })
                rowMenu.open(e)
              }}
            >
              <div className="txnCheckWrap" style={{ display: 'grid', placeItems: 'center' }}>
                <input
                  type="checkbox"
                  className="txnCheck"
                  checked={selectedIds.has(t.id)}
                  onChange={() => toggleSelection(t.id)}
                  onClick={(e) => e.stopPropagation()}
                />
              </div>
              <div className="txnIcon" data-tone={amountTone(t)}>
                <TransactionKindIcon kind={t.kind} />
              </div>
              <div className="txnMain">
                <div className="txnTitle">
                  <span className="txnTitleText">{txnTitle(t)}</span>
                  {(t.tags ?? []).includes('bank-csv') || (t.tags ?? []).includes('bank-pdf') ? <span className="pill">Imported</span> : null}
                </div>
                <div className="txnMeta">{txnSubtitle(t)}</div>
              </div>
              <div className="txnRight">
                <div className="txnAmount" data-tone={amountTone(t)}>
                  {currency(signedAmount(t), t.amount.currencyCode)}
                </div>
                <div className="txnDate">{toDateInputValue(t.date)}</div>
              </div>
            </div>
          ))}
          {filtered.length === 0 ? <div className="empty">No transactions match the current filters.</div> : null}
        </div>
        {rowMenu.Menu}

        {showEditor ? (
          <div className="detail">
            {selectedIds.size > 0 ? (
              <div className="form">
                <div className="groupBox">
                  <div className="groupTitle">Selection summary</div>
                  <div className="note">{selectedTx.length} selected</div>
                  <div className="fieldRow" style={{ marginTop: 10 }}>
                    <label className="field">
                      <div className="fieldLabel">Tax base</div>
                      <MenuSelect
                        value={taxBase}
                        options={[
                          { value: 'income', label: 'Income' },
                          { value: 'expense', label: 'Expenses' },
                          { value: 'net', label: 'Net' },
                        ]}
                        onChange={(v) => setTaxBase(v as any)}
                        width={220}
                      />
                    </label>
                    <label className="field">
                      <div className="fieldLabel">Tax %</div>
                      <input type="number" value={taxRatePct} onChange={(e) => setTaxRatePct(Number(e.target.value))} />
                    </label>
                  </div>
                  <label className="check" style={{ marginTop: 10 }}>
                    <input type="checkbox" checked={taxOverrideEnabled} onChange={(e) => setTaxOverrideEnabled(e.target.checked)} />
                    Override tax amount
                  </label>
                  {taxOverrideEnabled ? (
                    <label className="field" style={{ marginTop: 10 }}>
                      <div className="fieldLabel">Tax amount</div>
                      <input type="number" value={taxOverrideAmount} onChange={(e) => setTaxOverrideAmount(Number(e.target.value))} />
                    </label>
                  ) : null}

                  <div className="groupBox">
                    <div className="groupTitle">Totals</div>
                    <div className="progressRow">
                      <div className="note">Income</div>
                      <div className="progressValue">{currency(selectionTotals.income, state.settings.displayCurrencyCode)}</div>
                    </div>
                    <div className="progressRow" style={{ marginTop: 8 }}>
                      <div className="note">Expenses</div>
                      <div className="progressValue">{currency(selectionTotals.expense, state.settings.displayCurrencyCode)}</div>
                    </div>
                    <div className="progressRow" style={{ marginTop: 8 }}>
                      <div className="note">Net</div>
                      <div className="progressValue">{currency(selectionTotals.net, state.settings.displayCurrencyCode)}</div>
                    </div>
                    <div className="progressRow" style={{ marginTop: 8 }}>
                      <div className="note">Tax</div>
                      <div className="progressValue">{currency(selectionTotals.tax, state.settings.displayCurrencyCode)}</div>
                    </div>
                    <div className="progressRow" style={{ marginTop: 8 }}>
                      <div className="note">Total + Tax</div>
                      <div className="progressValue">{currency(selectionTotals.totalWithTax, state.settings.displayCurrencyCode)}</div>
                    </div>
                  </div>
                </div>
              </div>
            ) : selected ? (
              <div className="form">
                <div className="groupBox">
                  <div className="groupTitle">Basics</div>
                  <label className="field">
                    <div className="fieldLabel">Type</div>
                    <MenuSelect
                      value={selected.kind}
                      options={[
                        { value: 'expense', label: 'Expense' },
                        { value: 'income', label: 'Income' },
                        { value: 'transfer', label: 'Transfer' },
                      ]}
                      onChange={(v) => updateSelected({ kind: v as TransactionKind })}
                    />
                  </label>

                  <label className="field">
                    <div className="fieldLabel">Date</div>
                    <input type="date" value={toDateInputValue(selected.date)} onChange={(e) => updateSelected({ date: fromDateInputValue(e.target.value) })} />
                  </label>

                  <div className="fieldRow">
                    <label className="field">
                      <div className="fieldLabel">Amount</div>
                      <input
                        type="number"
                        value={selected.amount.value}
                        onChange={(e) => updateSelected({ amount: { ...selected.amount, value: Number(e.target.value) } })}
                      />
                    </label>
                    <label className="field">
                      <div className="fieldLabel">Currency</div>
                      <input
                        value={selected.amount.currencyCode}
                        onChange={(e) => updateSelected({ amount: { ...selected.amount, currencyCode: e.target.value } })}
                      />
                    </label>
                  </div>
                </div>

                <div className="groupBox">
                  <div className="groupTitle">Accounts</div>
                  <label className="field">
                    <div className="fieldLabel">Account</div>
                    <MenuSelect
                      value={(selected.accountId ?? '') as any}
                      placeholder="None"
                      options={[
                        { value: '' as any, label: 'None' },
                        ...activeAccounts.map((a) => ({ value: a.id as any, label: a.name })),
                      ]}
                      onChange={(v) => updateSelected({ accountId: v ? (v as UUID) : null })}
                      width={360}
                    />
                  </label>

                  {selected.kind === 'transfer' ? (
                    <label className="field">
                      <div className="fieldLabel">To Account</div>
                      <MenuSelect
                        value={(selected.toAccountId ?? '') as any}
                        placeholder="None"
                        options={[
                          { value: '' as any, label: 'None' },
                          ...activeAccounts.map((a) => ({ value: a.id as any, label: a.name })),
                        ]}
                        onChange={(v) => updateSelected({ toAccountId: v ? (v as UUID) : null })}
                        width={360}
                      />
                    </label>
                  ) : null}
                </div>

                {selected.kind === 'expense' ? (
                  <div className="groupBox">
                    <div className="groupTitle">Category</div>
                    <label className="field">
                      <div className="fieldLabel">Category</div>
                      <MenuSelect
                        value={(selected.category ?? 'other') as BillCategory}
                        options={categories.map((c) => ({ value: c, label: c }))}
                        onChange={(v) => updateSelected({ category: v as BillCategory })}
                      />
                    </label>
                    <label className="field">
                      <div className="fieldLabel">Custom Category</div>
                      <input value={selected.customCategoryName ?? ''} onChange={(e) => updateSelected({ customCategoryName: e.target.value || null })} />
                    </label>
                  </div>
                ) : null}

                <div className="groupBox">
                  <div className="groupTitle">Details</div>
                  <label className="field">
                    <div className="fieldLabel">Payee</div>
                    <input value={selected.payee ?? ''} onChange={(e) => updateSelected({ payee: e.target.value || null })} />
                  </label>

                  <label className="field">
                    <div className="fieldLabel">Notes</div>
                    <textarea value={selected.notes ?? ''} onChange={(e) => updateSelected({ notes: e.target.value || null })} />
                  </label>

                  <label className="field">
                    <div className="fieldLabel">Tags (comma separated)</div>
                    <input
                      value={(selected.tags ?? []).join(', ')}
                      onChange={(e) =>
                        updateSelected({
                          tags: e.target.value
                            .split(',')
                            .map((x) => x.trim())
                            .filter((x) => x.length > 0),
                        })
                      }
                    />
                  </label>
                </div>
              </div>
            ) : (
              <div className="empty">Select a transaction.</div>
            )}
          </div>
        ) : null}
      </div>
    </>
  )
}
