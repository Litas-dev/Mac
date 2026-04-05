import { useMemo } from 'react'
import { useAppStore } from '../../app/appStore'
import { billIsPaidFor, billIsSnoozedActive } from '../../domain/models'
import { currency } from '../../domain/finance'
import { calculateMonthSummary } from '../../domain/reports'

export function DashboardView() {
  const { state } = useAppStore()
  const now = new Date()

  const summary = useMemo(() => {
    const month = new Date(now.getFullYear(), now.getMonth(), 1)
    return calculateMonthSummary({ month, bills: state.bills, incomes: state.incomes })
  }, [now.getFullYear(), now.getMonth(), state.bills, state.incomes])

  const nextBill = useMemo(() => {
    const candidates = state.bills
      .filter((b) => {
        if (b.hiddenUntilEdited) return false
        if (billIsSnoozedActive(b, now)) return false
        if (billIsPaidFor(b, b.nextDueDate)) return false
        return true
      })
      .sort((a, b) => a.nextDueDate.getTime() - b.nextDueDate.getTime())
    return candidates[0] ?? null
  }, [now, state.bills])

  const forecast = useMemo(() => {
    const start = new Date(now)
    start.setHours(0, 0, 0, 0)
    const horizons = [7, 14, 30] as const
    const incomes = state.incomes
    const bills = state.bills
    const items = horizons.map((days) => {
      const endDate = new Date(start)
      endDate.setDate(endDate.getDate() + days)
      const incomeTotal = incomes.reduce((acc, i) => (i.nextPayDate >= start && i.nextPayDate <= endDate ? acc + i.amount.value : acc), 0)
      const billsTotal = bills.reduce((acc, b) => {
        if (b.hiddenUntilEdited) return acc
        if (billIsSnoozedActive(b, now)) return acc
        if (billIsPaidFor(b, b.nextDueDate)) return acc
        if (b.nextDueDate >= start && b.nextDueDate <= endDate) return acc + b.amount.value
        return acc
      }, 0)
      const net = incomeTotal - billsTotal
      return { days, end: net, min: Math.min(0, net) }
    })
    return items
  }, [now, state.bills, state.incomes])

  return (
    <>
      <div className="dashBanner">
        <div className="dashBannerDot" />
        <div>You are on track this month</div>
      </div>

      <div className="dashKpis">
        <div className="dashKpi">
          <div className="dashKpiLabel">Income This Month</div>
          <div className="dashKpiValue">{currency(summary.income, state.settings.displayCurrencyCode)}</div>
        </div>
        <div className="dashKpi">
          <div className="dashKpiLabel">Bills This Month</div>
          <div className="dashKpiValue">{currency(summary.bills, state.settings.displayCurrencyCode)}</div>
        </div>
        <div className="dashKpi">
          <div className="dashKpiLabel">Left After Bills</div>
          <div className="dashKpiValue">{currency(summary.net, state.settings.displayCurrencyCode)}</div>
        </div>
        <div className="dashKpi">
          <div className="dashKpiLabel">Next Bill</div>
          <div className="dashKpiValue" style={{ fontSize: 13, fontWeight: 700 }}>
            {nextBill ? nextBill.name : 'None'}
          </div>
        </div>
      </div>

      <div className="dashSection">
        <div className="dashSectionHeader">
          <div className="dashSectionTitle">Cash Flow Forecast</div>
          <div className="dashSectionChevron">▾</div>
        </div>
        <div className="dashForecast">
          {forecast.map((f) => (
            <div key={f.days} className="dashForecastCard">
              <div className="dashForecastDays">{f.days}d</div>
              <div className="dashForecastLine">
                <span className="dashForecastKey">End:</span>
                <span className="dashForecastVal">{currency(f.end, state.settings.displayCurrencyCode)}</span>
              </div>
              <div className="dashForecastLine">
                <span className="dashForecastKey">Min:</span>
                <span className="dashForecastVal">{currency(f.min, state.settings.displayCurrencyCode)}</span>
              </div>
            </div>
          ))}
        </div>
        <div className="dashOverdue">
          Overdue Total: {currency(0, state.settings.displayCurrencyCode)}
        </div>
      </div>
    </>
  )
}
