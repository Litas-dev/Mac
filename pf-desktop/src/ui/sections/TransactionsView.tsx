import { useMemo, useRef, useState } from 'react'
import { useAppStore } from '../../app/appStore'
import type { BillCategory, Transaction, TransactionKind, UUID } from '../../domain/models'
import { currency } from '../../domain/finance'
import { fromDateInputValue, toDateInputValue } from '../date'
import { parseCsvRows, rowsToTransactions } from '../../domain/csvImport'
import { useContextMenu } from '../ContextMenu'
import { MenuSelect } from '../MenuSelect'
import { TransactionKindIcon } from '../icons'

export function TransactionsView() {
  const { state, dispatch } = useAppStore()
  const selectedId = state.ui.selectedTransactionId
  const [search, setSearch] = useState('')
  const [accountFilterId, setAccountFilterId] = useState<UUID | 'all'>('all')
  const [kindFilter, setKindFilter] = useState<TransactionKind | 'all'>('all')
  const [sourceFilter, setSourceFilter] = useState<'all' | 'imported' | 'manual'>('all')
  const [dateFilter, setDateFilter] = useState<'all' | 'last30' | 'last90' | 'thisMonth'>('all')
  const [sort, setSort] = useState<'dateDesc' | 'dateAsc' | 'amountDesc' | 'amountAsc' | 'netDesc' | 'netAsc'>('dateDesc')
  const [showFilters, setShowFilters] = useState(false)
  const fileInputRef = useRef<HTMLInputElement | null>(null)

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
      if (sourceFilter === 'imported') items = items.filter((t) => (t.tags ?? []).includes('bank-csv'))
      if (sourceFilter === 'manual') items = items.filter((t) => !(t.tags ?? []).includes('bank-csv'))
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
  }, [accountFilterId, dateFilter, kindFilter, search, sort, sourceFilter, state.transactions])

  const selected = useMemo(() => {
    if (!selectedId) return null
    return state.transactions.find((t) => t.id === selectedId) ?? null
  }, [selectedId, state.transactions])

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

  function importCsvClick() {
    fileInputRef.current?.click()
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
    if (dateFilter !== 'all') c += 1
    if (sort !== 'dateDesc') c += 1
    return c
  }, [accountFilterId, dateFilter, kindFilter, sort, sourceFilter])

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
      parts.push(dateFilter === 'last30' ? 'Last 30 days' : dateFilter === 'last90' ? 'Last 90 days' : 'This month')
    }
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
  }, [accountFilterId, accountNameById, dateFilter, kindFilter, sort, sourceFilter])

  function clearFilters() {
    setAccountFilterId('all')
    setKindFilter('all')
    setSourceFilter('all')
    setDateFilter('all')
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
    if ((t.tags ?? []).includes('bank-csv')) parts.push('Imported')
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
            {filterSummary ? <div className="toolbarSubtitle">{filterSummary}</div> : null}
          </div>
          <div className="rowActions">
            <button type="button" onClick={() => setShowFilters(true)}>
              {activeFilterCount === 0 ? 'Filters' : `Filters ${activeFilterCount}`}
            </button>
            <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search" style={{ width: 180 }} />
            <button type="button" onClick={importCsvClick}>
              Import CSV
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
              onChange={(e) => void onPickCsv(e.target.files?.[0] ?? null)}
            />
          </div>
        </div>

        {showFilters ? <div className="popoverOverlay" onClick={() => setShowFilters(false)} /> : null}
        {showFilters ? (
          <div className="popoverPanel" role="dialog" aria-label="Filters">
            <div className="groupTitle" style={{ marginBottom: 8 }}>
              Filters
            </div>
            <div className="fieldRow">
              <label className="field" style={{ margin: 0 }}>
                <div className="fieldLabel">Account</div>
                <MenuSelect
                  value={accountFilterId}
                  options={[
                    { value: 'all', label: 'All Accounts' },
                    ...activeAccounts.map((a) => ({ value: a.id as any, label: a.name })),
                  ]}
                  onChange={(v) => setAccountFilterId(v as any)}
                  width={360}
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
                />
              </label>
            </div>

            <div className="fieldRow" style={{ marginTop: 10 }}>
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
                  ]}
                  onChange={(v) => setDateFilter(v as any)}
                />
              </label>
            </div>

            <div className="field" style={{ marginTop: 10 }}>
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
              />
            </div>

            <div className="rowActions" style={{ marginTop: 12, justifyContent: 'flex-end' }}>
              <button
                type="button"
                onClick={() => {
                  clearFilters()
                }}
                disabled={activeFilterCount === 0}
              >
                Clear
              </button>
              <button type="button" onClick={() => setShowFilters(false)}>
                Done
              </button>
            </div>
          </div>
        ) : null}
      </div>

      <div className="split">
        <div className="list">
          {filtered.map((t) => (
            <button
              key={t.id}
              type="button"
              className={t.id === selectedId ? 'listItem active txnRow' : 'listItem txnRow'}
              onClick={() => dispatch({ type: 'ui/selectTransaction', id: t.id })}
              onContextMenu={(e) => {
                dispatch({ type: 'ui/selectTransaction', id: t.id })
                rowMenu.open(e)
              }}
            >
              <div className="txnIcon" data-tone={amountTone(t)}>
                <TransactionKindIcon kind={t.kind} />
              </div>
              <div className="txnMain">
                <div className="txnTitle">
                  <span className="txnTitleText">{txnTitle(t)}</span>
                  {(t.tags ?? []).includes('bank-csv') ? <span className="pill">Imported</span> : null}
                </div>
                <div className="txnMeta">{txnSubtitle(t)}</div>
              </div>
              <div className="txnRight">
                <div className="txnAmount" data-tone={amountTone(t)}>
                  {currency(signedAmount(t), t.amount.currencyCode)}
                </div>
                <div className="txnDate">{toDateInputValue(t.date)}</div>
              </div>
            </button>
          ))}
          {filtered.length === 0 ? <div className="empty">No transactions match the current filters.</div> : null}
        </div>
        {rowMenu.Menu}

        <div className="detail">
          {selected ? (
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
      </div>
    </>
  )
}
