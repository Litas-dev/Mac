import { DashboardView } from './sections/DashboardView'
import { CalendarView } from './sections/CalendarView'
import { BillsView } from './sections/BillsView'
import { IncomeView } from './sections/IncomeView'
import { DueSoonView } from './sections/DueSoonView'
import { DeferredView } from './sections/DeferredView'
import { PaidRecentlyView } from './sections/PaidRecentlyView'
import { AccountsView } from './sections/AccountsView'
import { TransactionsView } from './sections/TransactionsView'
import { GoalsView } from './sections/GoalsView'
import { DebtsView } from './sections/DebtsView'
import { ReportsView } from './sections/ReportsView'
import { SettingsView } from './sections/SettingsView'
import { InvoicesView } from './sections/InvoicesView'
import { useAppStore } from '../app/appStore'

export function SectionRouter() {
  const { state } = useAppStore()
  switch (state.ui.section) {
    case 'dashboard':
      return <DashboardView />
    case 'calendar':
      return <CalendarView />
    case 'bills':
      return <BillsView />
    case 'income':
      return <IncomeView />
    case 'dueSoon':
      return <DueSoonView />
    case 'deferred':
      return <DeferredView />
    case 'paidRecently':
      return <PaidRecentlyView />
    case 'accounts':
      return <AccountsView />
    case 'transactions':
      return <TransactionsView />
    case 'invoices':
      return <InvoicesView />
    case 'goals':
      return <GoalsView />
    case 'debts':
      return <DebtsView />
    case 'reports':
      return <ReportsView />
    case 'settings':
      return <SettingsView />
  }
}
