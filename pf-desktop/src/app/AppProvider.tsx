import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from 'react'
import { AppStoreContext, type AppAction, type AppState, type AppStore, type Section } from './appStore'
import { defaultSettings } from '../domain/settings'
import type { LoadedDatasets } from '../storage/localJsonStore'
import { loadAllFromLocalStorage, saveAllToLocalStorage } from '../storage/localJsonStore'
import { isTauriRuntime, loadAllFromTauriFiles, saveAllToTauriFiles } from '../storage/tauriJsonStore'
import {
  advanceRecurrence,
  billClearSnooze,
  billMarkPaid,
  billSetSnooze,
  incomeLogReceipt,
  processAutoPayments,
  startOfDay,
} from '../domain/models'
import type { Transaction } from '../domain/models'
import { scheduleAllNotifications } from '../notifications/notificationScheduler'
import { applyAutostart } from '../desktop/autostart'

const ONBOARDING_KEY = 'Kivana/didCompleteOnboarding'

function loadOnboardingFlag(): boolean {
  try {
    return localStorage.getItem(ONBOARDING_KEY) === 'true'
  } catch {
    return false
  }
}

function saveOnboardingFlag(v: boolean): void {
  try {
    localStorage.setItem(ONBOARDING_KEY, v ? 'true' : 'false')
  } catch {
  }
}

function initialUI(): AppState['ui'] {
  return {
    section: 'dashboard',
    didCompleteOnboarding: loadOnboardingFlag(),
    selectedBillId: null,
    selectedIncomeId: null,
    selectedAccountId: null,
    selectedTransactionId: null,
    selectedGoalId: null,
    selectedDebtId: null,
  }
}

function reducer(state: AppState, action: AppAction): AppState {
  switch (action.type) {
    case 'ui/setSection':
      return { ...state, ui: { ...state.ui, section: action.section } }
    case 'ui/completeOnboarding':
      return { ...state, ui: { ...state.ui, didCompleteOnboarding: true } }
    case 'ui/selectBill':
      return { ...state, ui: { ...state.ui, selectedBillId: action.id } }
    case 'ui/selectIncome':
      return { ...state, ui: { ...state.ui, selectedIncomeId: action.id } }
    case 'ui/selectAccount':
      return { ...state, ui: { ...state.ui, selectedAccountId: action.id } }
    case 'ui/selectTransaction':
      return { ...state, ui: { ...state.ui, selectedTransactionId: action.id } }
    case 'ui/selectGoal':
      return { ...state, ui: { ...state.ui, selectedGoalId: action.id } }
    case 'ui/selectDebt':
      return { ...state, ui: { ...state.ui, selectedDebtId: action.id } }
    case 'data/replaceAll':
      return { ...action.data, ui: state.ui }
    case 'bills/add':
      return {
        ...state,
        bills: [...state.bills, action.bill],
        ui: { ...state.ui, selectedBillId: action.bill.id },
      }
    case 'bills/update':
      return {
        ...state,
        bills: state.bills.map((b) => (b.id === action.bill.id ? action.bill : b)),
        ui: { ...state.ui, selectedBillId: action.bill.id },
      }
    case 'bills/delete': {
      const nextBills = state.bills.filter((b) => b.id !== action.id)
      const nextSelected = state.ui.selectedBillId === action.id ? null : state.ui.selectedBillId
      return { ...state, bills: nextBills, ui: { ...state.ui, selectedBillId: nextSelected } }
    }
    case 'bills/logPayment': {
      const idx = state.bills.findIndex((b) => b.id === action.id)
      if (idx < 0) return state
      const b = state.bills[idx]
      const paidOn = action.date ?? b.nextDueDate
      const target = startOfDay(b.nextDueDate)
      const payDay = startOfDay(paidOn)
      let effectivePaidOn = paidOn
      if (b.recurrence !== 'once') {
        const prevDue = startOfDay(advanceRecurrence(b.recurrence, b.nextDueDate, -1))
        if (payDay.getTime() <= prevDue.getTime()) return state
        if (payDay.getTime() > target.getTime()) effectivePaidOn = b.nextDueDate
      }

      const updated = billMarkPaid(b, effectivePaidOn)
      const nextBills = [...state.bills]
      nextBills[idx] = updated
      const didAddPayment = updated.payments.length > b.payments.length
      if (!didAddPayment) return { ...state, bills: nextBills, ui: { ...state.ui, selectedBillId: null } }

      const tx: Transaction = {
        id: crypto.randomUUID(),
        kind: 'expense',
        date: effectivePaidOn,
        amount: { currencyCode: b.amount.currencyCode, value: Math.abs(b.amount.value) },
        accountId: state.accounts.find((a) => !a.archived)?.id ?? null,
        toAccountId: null,
        category: 'other',
        customCategoryName: null,
        payee: b.name,
        notes: null,
        tags: ['bill'],
        relatedBillId: b.id,
        relatedIncomeId: null,
      }

      const nextUI: AppState['ui'] =
        state.ui.section === 'bills'
          ? { ...state.ui, section: 'transactions', selectedBillId: null, selectedTransactionId: tx.id }
          : { ...state.ui, selectedBillId: null, selectedTransactionId: tx.id }

      return { ...state, bills: nextBills, transactions: [...state.transactions, tx], ui: nextUI }
    }
    case 'bills/skip': {
      const idx = state.bills.findIndex((b) => b.id === action.id)
      if (idx < 0) return state
      const b = state.bills[idx]
      const nextBills = [...state.bills]
      nextBills[idx] = { ...b, nextDueDate: advanceRecurrence(b.recurrence, b.nextDueDate) }
      return { ...state, bills: nextBills }
    }
    case 'bills/setSnooze': {
      const idx = state.bills.findIndex((b) => b.id === action.id)
      if (idx < 0) return state
      const b = state.bills[idx]
      const updated = billSetSnooze(b, action.until)
      const nextBills = [...state.bills]
      nextBills[idx] = updated
      return { ...state, bills: nextBills, ui: { ...state.ui, selectedBillId: updated.id } }
    }
    case 'bills/clearSnooze': {
      const idx = state.bills.findIndex((b) => b.id === action.id)
      if (idx < 0) return state
      const b = state.bills[idx]
      const updated = billClearSnooze(b)
      const nextBills = [...state.bills]
      nextBills[idx] = updated
      return { ...state, bills: nextBills, ui: { ...state.ui, selectedBillId: updated.id } }
    }
    case 'bills/deletePayment': {
      const idx = state.bills.findIndex((b) => b.id === action.id)
      if (idx < 0) return state
      const b = state.bills[idx]
      const nextBills = [...state.bills]
      nextBills[idx] = { ...b, payments: b.payments.filter((p) => p.id !== action.paymentId) }
      return { ...state, bills: nextBills, ui: { ...state.ui, selectedBillId: b.id } }
    }
    case 'incomes/add':
      return {
        ...state,
        incomes: [...state.incomes, action.income],
        ui: { ...state.ui, selectedIncomeId: action.income.id },
      }
    case 'incomes/update':
      return {
        ...state,
        incomes: state.incomes.map((i) => (i.id === action.income.id ? action.income : i)),
        ui: { ...state.ui, selectedIncomeId: action.income.id },
      }
    case 'incomes/delete': {
      const next = state.incomes.filter((i) => i.id !== action.id)
      const sel = state.ui.selectedIncomeId === action.id ? null : state.ui.selectedIncomeId
      return { ...state, incomes: next, ui: { ...state.ui, selectedIncomeId: sel } }
    }
    case 'incomes/logReceipt': {
      const idx = state.incomes.findIndex((i) => i.id === action.id)
      if (idx < 0) return state
      const inc = state.incomes[idx]
      const receivedOn = action.date ?? new Date()
      const updated = incomeLogReceipt(inc, receivedOn)
      const nextIncomes = [...state.incomes]
      nextIncomes[idx] = updated
      const didAddReceipt = updated.receipts.length > inc.receipts.length
      if (!didAddReceipt) return { ...state, incomes: nextIncomes, ui: { ...state.ui, selectedIncomeId: updated.id } }

      const tx: Transaction = {
        id: crypto.randomUUID(),
        kind: 'income',
        date: receivedOn,
        amount: { currencyCode: inc.amount.currencyCode, value: Math.abs(inc.amount.value) },
        accountId: state.accounts.find((a) => !a.archived)?.id ?? null,
        toAccountId: null,
        category: null,
        customCategoryName: null,
        payee: inc.name,
        notes: null,
        tags: ['income'],
        relatedBillId: null,
        relatedIncomeId: inc.id,
      }

      const nextUI: AppState['ui'] =
        state.ui.section === 'income'
          ? { ...state.ui, section: 'transactions', selectedIncomeId: updated.id, selectedTransactionId: tx.id }
          : { ...state.ui, selectedIncomeId: updated.id, selectedTransactionId: tx.id }

      return { ...state, incomes: nextIncomes, transactions: [...state.transactions, tx], ui: nextUI }
    }
    case 'incomes/skip': {
      const idx = state.incomes.findIndex((i) => i.id === action.id)
      if (idx < 0) return state
      const inc = state.incomes[idx]
      const nextIncomes = [...state.incomes]
      nextIncomes[idx] = { ...inc, nextPayDate: advanceRecurrence(inc.recurrence, inc.nextPayDate) }
      return { ...state, incomes: nextIncomes, ui: { ...state.ui, selectedIncomeId: inc.id } }
    }
    case 'accounts/add':
      return {
        ...state,
        accounts: [...state.accounts, action.account],
        ui: { ...state.ui, selectedAccountId: action.account.id },
      }
    case 'accounts/update':
      return {
        ...state,
        accounts: state.accounts.map((a) => (a.id === action.account.id ? action.account : a)),
        ui: { ...state.ui, selectedAccountId: action.account.id },
      }
    case 'accounts/delete': {
      const nextAccounts = state.accounts.filter((a) => a.id !== action.id)
      const nextSelected = state.ui.selectedAccountId === action.id ? null : state.ui.selectedAccountId
      const nextTransactions = state.transactions.map((t) => {
        if (t.accountId === action.id) return { ...t, accountId: null }
        if (t.toAccountId === action.id) return { ...t, toAccountId: null }
        return t
      })
      return { ...state, accounts: nextAccounts, transactions: nextTransactions, ui: { ...state.ui, selectedAccountId: nextSelected } }
    }
    case 'transactions/add':
      return {
        ...state,
        transactions: [...state.transactions, action.transaction],
        ui: { ...state.ui, selectedTransactionId: action.transaction.id },
      }
    case 'transactions/update':
      return {
        ...state,
        transactions: state.transactions.map((t) => (t.id === action.transaction.id ? action.transaction : t)),
        ui: { ...state.ui, selectedTransactionId: action.transaction.id },
      }
    case 'transactions/delete': {
      const next = state.transactions.filter((t) => t.id !== action.id)
      const sel = state.ui.selectedTransactionId === action.id ? null : state.ui.selectedTransactionId
      return { ...state, transactions: next, ui: { ...state.ui, selectedTransactionId: sel } }
    }
    case 'goals/add':
      return {
        ...state,
        goals: [...state.goals, action.goal],
        ui: { ...state.ui, selectedGoalId: action.goal.id },
      }
    case 'goals/update':
      return {
        ...state,
        goals: state.goals.map((g) => (g.id === action.goal.id ? action.goal : g)),
        ui: { ...state.ui, selectedGoalId: action.goal.id },
      }
    case 'goals/delete': {
      const next = state.goals.filter((g) => g.id !== action.id)
      const sel = state.ui.selectedGoalId === action.id ? null : state.ui.selectedGoalId
      return { ...state, goals: next, ui: { ...state.ui, selectedGoalId: sel } }
    }
    case 'debts/add':
      return {
        ...state,
        debts: [...state.debts, action.debt],
        ui: { ...state.ui, selectedDebtId: action.debt.id },
      }
    case 'debts/update':
      return {
        ...state,
        debts: state.debts.map((d) => (d.id === action.debt.id ? action.debt : d)),
        ui: { ...state.ui, selectedDebtId: action.debt.id },
      }
    case 'debts/delete': {
      const next = state.debts.filter((d) => d.id !== action.id)
      const sel = state.ui.selectedDebtId === action.id ? null : state.ui.selectedDebtId
      return { ...state, debts: next, ui: { ...state.ui, selectedDebtId: sel } }
    }
  }
}

function emptyDatasets(): LoadedDatasets {
  return {
    settings: defaultSettings(),
    bills: [],
    incomes: [],
    accounts: [],
    transactions: [],
    goals: [],
    debts: [],
  }
}

export function AppProvider({ children }: { children: React.ReactNode }) {
  const [ready, setReady] = useState(false)
  const [state, dispatch] = useReducer(reducer, null, () => ({ ...emptyDatasets(), ui: initialUI() }))
  const lastPersisted = useRef<string>('')
  const persistTimer = useRef<number | null>(null)

  const storageMode = useMemo(() => (isTauriRuntime() ? 'tauriFiles' : 'localStorage'), [])

  const serializeForPersist = useCallback((s: AppState) => {
    const { ui, ...datasets } = s
    return JSON.stringify(datasets)
  }, [])

  const persistNow = useCallback(async () => {
    if (!ready) return
    const fingerprint = serializeForPersist(state)
    if (fingerprint === lastPersisted.current) return
    const datasets: LoadedDatasets = {
      settings: state.settings,
      bills: state.bills,
      incomes: state.incomes,
      accounts: state.accounts,
      transactions: state.transactions,
      goals: state.goals,
      debts: state.debts,
    }
    if (storageMode === 'tauriFiles') {
      await saveAllToTauriFiles(datasets)
    } else {
      saveAllToLocalStorage(datasets)
    }
    lastPersisted.current = fingerprint
  }, [ready, serializeForPersist, state, storageMode])

  useEffect(() => {
    async function load() {
      const fallback = defaultSettings()
      const loaded = storageMode === 'tauriFiles' ? await loadAllFromTauriFiles(fallback) : loadAllFromLocalStorage(fallback)
      const billsAfterAuto = processAutoPayments(loaded.bills, new Date())
      const datasets = billsAfterAuto === loaded.bills ? loaded : { ...loaded, bills: billsAfterAuto }
      dispatch({ type: 'data/replaceAll', data: datasets })
      lastPersisted.current = JSON.stringify(datasets)
      setReady(true)
    }
    void load()
  }, [storageMode])

  useEffect(() => {
    if (!ready) return
    saveOnboardingFlag(state.ui.didCompleteOnboarding)
  }, [ready, state.ui.didCompleteOnboarding])

  useEffect(() => {
    if (!ready) return
    void scheduleAllNotifications(state.bills, state.settings, new Date())
  }, [ready, state.bills, state.settings])

  useEffect(() => {
    if (!ready) return
    void applyAutostart(state.settings.startOnLogin)
  }, [ready, state.settings.startOnLogin])

  useEffect(() => {
    if (!ready) return
    if (persistTimer.current) window.clearTimeout(persistTimer.current)
    persistTimer.current = window.setTimeout(() => {
      void persistNow()
    }, 150)
  }, [persistNow, ready, state])

  useEffect(() => {
    return () => {
      if (persistTimer.current) window.clearTimeout(persistTimer.current)
    }
  }, [])

  const store: AppStore = useMemo(() => ({ state, dispatch, persistNow }), [dispatch, persistNow, state])

  if (!ready) return null
  return <AppStoreContext.Provider value={store}>{children}</AppStoreContext.Provider>
}

export function setSection(section: Section): AppAction {
  return { type: 'ui/setSection', section }
}
