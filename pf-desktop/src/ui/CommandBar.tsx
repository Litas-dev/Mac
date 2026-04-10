import { useEffect, useMemo, useState } from 'react'
import { listen } from '@tauri-apps/api/event'
import { parseWithAI } from '../ai/aiParser'
import type { AICommand } from '../ai/commands'
import { dispatchTransactionsAutomation, parseTransactionsAutomationCommand } from '../ai/experimentalGuiAutomation'
import type { Bill, Income, Transaction } from '../domain/models'
import { fromDateInputValue } from './date'
import { useAppStore } from '../app/appStore'
import { isTauriRuntime } from '../storage/tauriJsonStore'

export function CommandBar() {
  const { state, dispatch } = useAppStore()
  const [input, setInput] = useState('')
  const [isParsing, setIsParsing] = useState(false)
  const enableGuiAutomation =
    (import.meta.env.DEV && import.meta.env.VITE_ENABLE_AI_GUI !== '0') || import.meta.env.VITE_ENABLE_AI_GUI === '1'
  const canRun = useMemo(() => input.trim().length > 0 && !isParsing, [input, isParsing])

  useEffect(() => {
    if (!isTauriRuntime()) return
    let unsub: (() => void) | null = null
    void listen('touchbar:parse', () => {
      if (input.trim().length === 0) return
      void runParse()
    }).then((u) => {
      unsub = u
    })
    return () => {
      unsub?.()
    }
  }, [input])

  async function runParse() {
    setIsParsing(true)
    try {
      if (enableGuiAutomation) {
        const req = parseTransactionsAutomationCommand(input)
        if (req) {
          dispatch({ type: 'ui/setSection', section: 'transactions' })
          dispatchTransactionsAutomation(req)
          setInput('')
          return
        }
      }
      const parsed = await parseWithAI(input, state.settings)
      applyCommand(parsed.command)
      setInput('')
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      window.alert('AI parsing failed: ' + msg)
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
        category: p.category ?? (p.kind === 'expense' ? 'other' : null),
        customCategoryName: p.customCategoryName ?? null,
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
        category: p.category ?? 'other',
        customCategoryName: p.customCategoryName ?? null,
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

  return (
    <div className="cmdBar">
      <input
        className="cmdInput"
        value={input}
        onChange={(e) => setInput(e.target.value)}
        placeholder="Command: pay | schedule | income | expense"
        onKeyDown={(e) => {
          if (e.key === 'Enter') void runParse()
        }}
      />
      <button type="button" className="cmdButton" onClick={() => void runParse()} disabled={!canRun}>
        {isParsing ? 'Parsing…' : 'Parse'}
      </button>
    </div>
  )
}
