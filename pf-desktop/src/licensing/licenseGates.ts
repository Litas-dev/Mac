import type { EntitlementsResponse } from './entitlementsApi'

export function isAdvancedAccount(entitlements: EntitlementsResponse | null): boolean {
  const p = entitlements?.products?.find((x) => x.productCode === 'kivana') ?? entitlements?.products?.[0]
  if (!p) return false
  const code = String(p.planCode || '').toLowerCase()
  return code === 'pro' || code === 'lifetime_pro'
}
