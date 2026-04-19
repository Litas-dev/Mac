const DISPLAY_CURRENCY_KEY = 'Kivana/prefs/displayCurrencyCode'
const LAST_LOGIN_EMAIL_KEY = 'Kivana/prefs/lastLoginEmail'

export function loadPreferredDisplayCurrencyCode(): string | null {
  try {
    const v = localStorage.getItem(DISPLAY_CURRENCY_KEY)
    const s = String(v ?? '').trim().toUpperCase()
    return s || null
  } catch {
    return null
  }
}

export function savePreferredDisplayCurrencyCode(code: string | null | undefined): void {
  try {
    const s = String(code ?? '').trim().toUpperCase()
    if (!s) return
    localStorage.setItem(DISPLAY_CURRENCY_KEY, s)
  } catch {
  }
}

export function loadLastLoginEmail(): string {
  try {
    return String(localStorage.getItem(LAST_LOGIN_EMAIL_KEY) ?? '').trim()
  } catch {
    return ''
  }
}

export function saveLastLoginEmail(email: string | null | undefined): void {
  try {
    const s = String(email ?? '').trim()
    if (!s) return
    localStorage.setItem(LAST_LOGIN_EMAIL_KEY, s)
  } catch {
  }
}

export function preservePrefsAcrossLocalStorageClear(): void {
  const currency = loadPreferredDisplayCurrencyCode()
  const email = loadLastLoginEmail()
  try {
    localStorage.clear()
  } catch {
    return
  }
  if (currency) savePreferredDisplayCurrencyCode(currency)
  if (email) saveLastLoginEmail(email)
}
