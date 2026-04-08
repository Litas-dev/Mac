import type { Bill, BillCategory } from './models'

export type DashboardStyle = 'basic' | 'advanced'

export type AIProvider = 'local' | 'external'

export type TextSize = 'small' | 'normal' | 'large'

export type Theme = 'system' | 'light' | 'dark'

export type AccentColor =
  | 'blue'
  | 'purple'
  | 'pink'
  | 'red'
  | 'orange'
  | 'yellow'
  | 'green'
  | 'mint'
  | 'teal'
  | 'cyan'
  | 'indigo'
  | 'gray'

export interface AppSettings {
  displayCurrencyCode: string
  enableNotifications: boolean
  reminderDays: number
  startOnLogin: boolean
  shareAnonymousData: boolean
  customBillCategories: string[]
  customIncomeCategories: string[]
  budgetCategories: string[]
  dashboardStyle: DashboardStyle
  iCloudEnabled: boolean
  calendarSyncEnabled: boolean
  calendarSyncCalendarName: string
  calendarSyncMonthsAhead: number
  calendarSyncLeadDays: number
  aiBaseURL: string
  aiModel: string
  aiProvider: AIProvider
  aiExternalEndpoint: string
  textSize: TextSize
  theme: Theme
  accentColor: AccentColor
  monthlyBudgets: Record<string, number>
  availableBalance: number
  preferManualForecastBalance: boolean
  hideAccountBalances: boolean
  aiExternalAPIKey?: string | null
}

export function defaultSettings(): AppSettings {
  return {
    displayCurrencyCode: 'NOK',
    enableNotifications: true,
    reminderDays: 7,
    startOnLogin: false,
    shareAnonymousData: true,
    customBillCategories: [],
    customIncomeCategories: [],
    budgetCategories: [],
    dashboardStyle: 'advanced',
    iCloudEnabled: true,
    calendarSyncEnabled: true,
    calendarSyncCalendarName: 'Bills',
    calendarSyncMonthsAhead: 3,
    calendarSyncLeadDays: 3,
    aiBaseURL: 'http://localhost:11434',
    aiModel: 'qwen3.5:4b',
    aiProvider: 'local',
    aiExternalEndpoint: 'https://api.groq.com/openai/v1/chat/completions',
    textSize: 'normal',
    theme: 'system',
    accentColor: 'blue',
    monthlyBudgets: {},
    availableBalance: 0,
    preferManualForecastBalance: false,
    hideAccountBalances: false,
    aiExternalAPIKey: null,
  }
}

export function budgetKeyBuiltin(category: BillCategory): string {
  return `builtin:${category}`
}

export function budgetKeyCustom(label: string): string {
  return `custom:${label}`
}

export function budgetDisplayName(key: string): string {
  if (key.startsWith('builtin:')) return capitalize(key.slice('builtin:'.length))
  if (key.startsWith('custom:')) return key.slice('custom:'.length)
  return key
}

export function budgetKeyForBill(bill: Bill): string {
  const label = bill.customCategoryName?.trim()
  if (label) return budgetKeyCustom(label)
  return budgetKeyBuiltin(bill.category)
}

export function migratedBudgets(settings: AppSettings): AppSettings {
  const migrated: Record<string, number> = {}
  for (const [k, v] of Object.entries(settings.monthlyBudgets ?? {})) {
    if (k.startsWith('builtin:') || k.startsWith('custom:')) {
      migrated[k] = v
      continue
    }
    if (isBillCategory(k)) {
      migrated[budgetKeyBuiltin(k)] = v
      continue
    }
    migrated[budgetKeyCustom(k)] = v
  }
  return { ...settings, monthlyBudgets: migrated }
}

export function migratedBudgetCategories(settings: AppSettings): AppSettings {
  if ((settings.budgetCategories?.length ?? 0) > 0) return settings
  const inferred = Object.keys(settings.monthlyBudgets ?? {})
    .filter((k) => k.startsWith('custom:'))
    .map((k) => k.slice('custom:'.length).trim())
    .filter((x) => x.length > 0)
  if (inferred.length === 0) return settings
  const unique = Array.from(new Set(inferred)).sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }))
  return { ...settings, budgetCategories: unique }
}

function capitalize(s: string): string {
  if (!s) return s
  return s.charAt(0).toUpperCase() + s.slice(1)
}

function isBillCategory(x: string): x is BillCategory {
  return (
    x === 'housing' ||
    x === 'utilities' ||
    x === 'subscriptions' ||
    x === 'insurance' ||
    x === 'taxes' ||
    x === 'transport' ||
    x === 'other'
  )
}
