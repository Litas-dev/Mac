import { listen } from '@tauri-apps/api/event'
import type { AppState } from '../app/appStore'
import { setSection } from '../app/AppProvider'
import { exportBackup, importBackupFromFolder, importBackupFromJson } from './dataActions'

export async function registerMenuEvents(getState: () => AppState, dispatch: (a: any) => void): Promise<() => void> {
  const unsubs: Array<() => void> = []

  async function handleExport() {
    const state = getState()
    const datasets = {
      settings: state.settings,
      bills: state.bills,
      incomes: state.incomes,
      accounts: state.accounts,
      transactions: state.transactions,
      invoices: state.invoices,
      goals: state.goals,
      debts: state.debts,
    }
    await exportBackup(datasets)
  }

  unsubs.push(
    await listen('menu:export_backup', () => {
      void handleExport()
    }),
  )
  unsubs.push(
    await listen('menu:import_backup_folder', () => {
      const state = getState()
      const datasets = {
        settings: state.settings,
        bills: state.bills,
        incomes: state.incomes,
        accounts: state.accounts,
        transactions: state.transactions,
        invoices: state.invoices,
        goals: state.goals,
        debts: state.debts,
      }
      void importBackupFromFolder(dispatch, datasets)
    }),
  )
  unsubs.push(
    await listen('menu:import_backup_json', () => {
      const state = getState()
      const datasets = {
        settings: state.settings,
        bills: state.bills,
        incomes: state.incomes,
        accounts: state.accounts,
        transactions: state.transactions,
        invoices: state.invoices,
        goals: state.goals,
        debts: state.debts,
      }
      void importBackupFromJson(dispatch, datasets)
    }),
  )
  unsubs.push(
    await listen('menu:open_settings', () => {
      dispatch(setSection('settings'))
    }),
  )

  return () => {
    for (const u of unsubs) u()
  }
}
