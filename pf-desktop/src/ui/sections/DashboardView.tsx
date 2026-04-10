import { useMemo } from 'react'
import { useAppStore } from '../../app/appStore'
import { setSection } from '../../app/AppProvider'
import { billIsPaidFor, billIsSnoozedActive } from '../../domain/models'
import { currency } from '../../domain/finance'
import { calculateMonthSummary } from '../../domain/reports'
import { toDateInputValue } from '../date'

export function DashboardView() {
  const { state, dispatch } = useAppStore()
  const now = new Date()

  const summary = useMemo(() => {
    const month = new Date(now.getFullYear(), now.getMonth(), 1)
    return calculateMonthSummary({ month, bills: state.bills, incomes: state.incomes, transactions: state.transactions })
  }, [now.getFullYear(), now.getMonth(), state.bills, state.incomes, state.transactions])

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

  const overdue = useMemo(() => {
    const start = new Date(now)
    start.setHours(0, 0, 0, 0)
    const items = state.bills
      .filter((b) => {
        if (b.hiddenUntilEdited) return false
        if (billIsSnoozedActive(b, now)) return false
        if (billIsPaidFor(b, b.nextDueDate)) return false
        const d = new Date(b.nextDueDate)
        d.setHours(0, 0, 0, 0)
        return d.getTime() < start.getTime()
      })
      .sort((a, b) => a.nextDueDate.getTime() - b.nextDueDate.getTime())

    const sameCurrency = items.every((b) => b.amount.currencyCode === items[0]?.amount.currencyCode)
    const code = items.length > 0 && sameCurrency ? items[0].amount.currencyCode : state.settings.displayCurrencyCode
    const total = items.reduce((acc, b) => acc + b.amount.value, 0)
    return { items, total, code }
  }, [now, state.bills, state.settings.displayCurrencyCode])

  const dueNext7 = useMemo(() => {
    const start = new Date(now)
    start.setHours(0, 0, 0, 0)
    const cutoff = new Date(start)
    cutoff.setDate(cutoff.getDate() + 7)
    return state.bills
      .filter((b) => {
        if (b.hiddenUntilEdited) return false
        if (billIsSnoozedActive(b, now)) return false
        if (billIsPaidFor(b, b.nextDueDate)) return false
        const d = new Date(b.nextDueDate)
        d.setHours(0, 0, 0, 0)
        return d.getTime() >= start.getTime() && d.getTime() <= cutoff.getTime()
      })
      .sort((a, b) => a.nextDueDate.getTime() - b.nextDueDate.getTime())
  }, [now, state.bills])

  function openBill(id: string) {
    dispatch({ type: 'ui/selectBill', id })
    dispatch(setSection('bills'))
  }

  function markPaid(id: string) {
    const bill = state.bills.find((b) => b.id === id)
    if (!bill) return
    dispatch({ type: 'bills/logPayment', id, date: bill.nextDueDate })
  }

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
          Overdue Total: {currency(overdue.total, overdue.code)}
        </div>
      </div>

      <div className="dashSection">
        <div className="dashSectionHeader">
          <div className="dashSectionTitle">Bills Due</div>
          <div className="dashSectionChevron">▾</div>
        </div>

        {overdue.items.length === 0 && dueNext7.length === 0 ? (
          <div className="note" style={{ marginTop: 12 }}>
            All paid.
          </div>
        ) : (
          <div className="list" style={{ marginTop: 12 }}>
            {overdue.items.map((b) => (
              <div key={b.id} className="note" style={{ display: 'grid', gridTemplateColumns: '1fr auto auto', gap: 8, padding: '10px 12px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
                <div style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {b.name} • {toDateInputValue(b.nextDueDate)}
                </div>
                <div>{currency(b.amount.value, b.amount.currencyCode)}</div>
                <button type="button" onClick={() => markPaid(b.id)} style={{ padding: '2px 8px' }}>
                  Paid
                </button>
                <button type="button" onClick={() => openBill(b.id)} style={{ padding: '2px 8px', gridColumn: '1 / -1' }}>
                  Open
                </button>
              </div>
            ))}

            {dueNext7.map((b) => (
              <div key={b.id} className="note" style={{ display: 'grid', gridTemplateColumns: '1fr auto auto', gap: 8, padding: '10px 12px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
                <div style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {b.name} • {toDateInputValue(b.nextDueDate)}
                </div>
                <div>{currency(b.amount.value, b.amount.currencyCode)}</div>
                <button type="button" onClick={() => markPaid(b.id)} style={{ padding: '2px 8px' }}>
                  Paid
                </button>
                <button type="button" onClick={() => openBill(b.id)} style={{ padding: '2px 8px', gridColumn: '1 / -1' }}>
                  Open
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </>
  )
}
