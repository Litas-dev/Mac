import { useEffect, useMemo, useState } from 'react'
import { useAppStore } from '../../app/appStore'
import { parseWithAI } from '../../ai/aiParser'
import type { AICommand } from '../../ai/commands'
import { loadCommandMemory, saveCommandMemory, type CommandMemoryItem } from '../../storage/commandMemory'
import type { Bill, Income, Transaction } from '../../domain/models'
import { fromDateInputValue, toDateInputValue } from '../date'

export function AIView() {
  const { state, dispatch } = useAppStore()
  const [input, setInput] = useState('')
  const [isParsing, setIsParsing] = useState(false)
  const [result, setResult] = useState<{ command: AICommand; raw: string } | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [memory, setMemory] = useState<CommandMemoryItem[]>([])

  useEffect(() => {
    let cancelled = false
    async function load() {
      const mem = await loadCommandMemory()
      if (cancelled) return
      setMemory(mem.items.slice().sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 50))
    }
    void load()
    return () => {
      cancelled = true
    }
  }, [])

  const canRun = useMemo(() => input.trim().length > 0 && !isParsing, [input, isParsing])

  async function runParse() {
    setError(null)
    setIsParsing(true)
    try {
      const parsed = await parseWithAI(input, state.settings)
      setResult({ command: parsed.command, raw: parsed.raw })

      const mem = await loadCommandMemory()
      const item: CommandMemoryItem = {
        id: crypto.randomUUID(),
        createdAt: new Date().toISOString(),
        input,
        command: parsed.command,
        raw: parsed.raw,
        favorite: false,
      }
      const next = { version: 1 as const, items: [item, ...mem.items].slice(0, 200) }
      await saveCommandMemory(next)
      setMemory(next.items.slice(0, 50))
    } catch (e: any) {
      setError(String(e?.message ?? e ?? 'Unknown error'))
      setResult(null)
    } finally {
      setIsParsing(false)
    }
  }

  function applyCommand(cmd: AICommand) {
    if (cmd.type === 'createTransaction') {
      const p = cmd.payload
      const t: Transaction = {
        id: crypto.randomUUID(),
        kind: p.kind,
        date: new Date(),
        amount: { currencyCode: p.currencyCode ?? state.settings.displayCurrencyCode, value: Math.abs(p.amount) },
        accountId: state.accounts.find((a) => !a.archived)?.id ?? null,
        toAccountId: null,
        category: p.kind === 'expense' ? 'other' : null,
        customCategoryName: null,
        payee: p.payee ?? null,
        notes: p.notes ?? null,
        tags: ['ai'],
        relatedBillId: null,
        relatedIncomeId: null,
      }
      dispatch({ type: 'transactions/add', transaction: t })
      dispatch({ type: 'ui/setSection', section: 'transactions' })
      dispatch({ type: 'ui/selectTransaction', id: t.id })
      return
    }
    if (cmd.type === 'createBill') {
      const p = cmd.payload
      const due = p.dueDate ? fromDateInputValue(p.dueDate) : new Date()
      const b: Bill = {
        id: crypto.randomUUID(),
        name: p.name,
        amount: { currencyCode: p.currencyCode ?? state.settings.displayCurrencyCode, value: Math.abs(p.amount) },
        category: 'other',
        customCategoryName: null,
        recurrence: 'monthly',
        nextDueDate: due,
        notes: null,
        payments: [],
        paidAutomatically: false,
        hiddenUntilEdited: false,
        snoozeUntil: null,
        snoozeCount: 0,
        attachments: [],
      }
      dispatch({ type: 'bills/add', bill: b })
      dispatch({ type: 'ui/setSection', section: 'bills' })
      dispatch({ type: 'ui/selectBill', id: b.id })
      return
    }
    if (cmd.type === 'createIncome') {
      const p = cmd.payload
      const d = p.nextPayDate ? fromDateInputValue(p.nextPayDate) : new Date()
      const i: Income = {
        id: crypto.randomUUID(),
        name: p.name,
        amount: { currencyCode: p.currencyCode ?? state.settings.displayCurrencyCode, value: Math.abs(p.amount) },
        source: 'other',
        customSourceName: null,
        recurrence: 'monthly',
        nextPayDate: d,
        notes: null,
        receipts: [],
      }
      dispatch({ type: 'incomes/add', income: i })
      dispatch({ type: 'ui/setSection', section: 'income' })
      dispatch({ type: 'ui/selectIncome', id: i.id })
      return
    }
    window.alert(cmd.payload.message)
  }

  function toggleFavorite(id: string) {
    void (async () => {
      const mem = await loadCommandMemory()
      const nextItems = mem.items.map((i) => (i.id === id ? { ...i, favorite: !i.favorite } : i))
      const next = { version: 1 as const, items: nextItems }
      await saveCommandMemory(next)
      setMemory(nextItems.slice().sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 50))
    })()
  }

  return (
    <>
      <div className="form">
        <label className="field">
          <div className="fieldLabel">Command</div>
          <input value={input} onChange={(e) => setInput(e.target.value)} placeholder='e.g. "spent 25 on groceries"' />
        </label>
        <div className="rowActions">
          <button type="button" onClick={() => void runParse()} disabled={!canRun}>
            {isParsing ? 'Parsing…' : 'Parse'}
          </button>
          <button type="button" onClick={() => setInput('')}>
            Clear
          </button>
        </div>
        {error ? <div className="note">{error}</div> : null}

        {result ? (
          <div className="field">
            <div className="fieldLabel">Preview</div>
            <div className="note" style={{ whiteSpace: 'pre-wrap' }}>
              {JSON.stringify(result.command, null, 2)}
            </div>
            <div className="rowActions" style={{ marginTop: 8 }}>
              <button type="button" onClick={() => applyCommand(result.command)}>
                Apply
              </button>
            </div>
          </div>
        ) : null}

        <div className="field">
          <div className="fieldLabel">Recent</div>
          {memory.length === 0 ? (
            <div className="note">No commands yet.</div>
          ) : (
            memory.map((m) => (
              <div key={m.id} className="note" style={{ display: 'grid', gridTemplateColumns: '1fr auto auto', gap: 8 }}>
                <div style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {toDateInputValue(new Date(m.createdAt))} • {m.input}
                </div>
                <button type="button" onClick={() => toggleFavorite(m.id)} style={{ padding: '2px 8px' }}>
                  {m.favorite ? '★' : '☆'}
                </button>
                <button type="button" onClick={() => applyCommand(m.command)} style={{ padding: '2px 8px' }}>
                  Apply
                </button>
              </div>
            ))
          )}
        </div>
      </div>
    </>
  )
}
