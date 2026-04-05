import { useMemo, useState } from 'react'
import { useAppStore } from '../../app/appStore'
import { currency } from '../../domain/finance'
import { calculateMonthSummary } from '../../domain/reports'
import { toDateInputValue } from '../date'

export function ReportsView() {
  const { state } = useAppStore()
  const [month, setMonth] = useState(() => {
    const d = new Date()
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
  })

  const selectedMonthDate = useMemo(() => {
    const [y, m] = month.split('-').map((x) => Number(x))
    if (!Number.isFinite(y) || !Number.isFinite(m)) return new Date()
    return new Date(y, m - 1, 1)
  }, [month])

  const summary = useMemo(() => {
    return calculateMonthSummary({ month: selectedMonthDate, bills: state.bills, incomes: state.incomes })
  }, [selectedMonthDate, state.bills, state.incomes])

  const expectedIncome = summary.incomeDetails.filter((x) => !x.isPaid)
  const receivedIncome = summary.incomeDetails.filter((x) => x.isPaid)
  const dueBills = summary.billDetails.filter((x) => !x.isPaid)
  const paidBills = summary.billDetails.filter((x) => x.isPaid)

  return (
    <>
      <div className="row" style={{ marginTop: 8 }}>
        <div className="rowActions">
          <label className="field" style={{ margin: 0 }}>
            <div className="fieldLabel">Month</div>
            <input type="month" value={month} onChange={(e) => setMonth(e.target.value)} />
          </label>
        </div>
      </div>

      <div className="grid" style={{ marginTop: 12 }}>
        <div className="card">
          <div className="cardLabel">Expected Income</div>
          <div className="cardValue">{currency(summary.income, state.settings.displayCurrencyCode)}</div>
        </div>
        <div className="card">
          <div className="cardLabel">Expected Bills</div>
          <div className="cardValue">{currency(summary.bills, state.settings.displayCurrencyCode)}</div>
        </div>
        <div className="card">
          <div className="cardLabel">Expected Net</div>
          <div className="cardValue">{currency(summary.net, state.settings.displayCurrencyCode)}</div>
        </div>
      </div>

      <div className="field" style={{ marginTop: 16 }}>
        <div className="fieldLabel">Income</div>
        {expectedIncome.length === 0 && receivedIncome.length === 0 ? (
          <div className="note">No income items for this month.</div>
        ) : (
          <>
            {expectedIncome.length ? (
              <>
                <div className="note">Expected</div>
                {expectedIncome.map((i) => (
                  <div key={i.id} className="note" style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                    <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{i.name}</span>
                    <span>{toDateInputValue(i.date)}</span>
                    <span>{currency(i.amount, state.settings.displayCurrencyCode)}</span>
                  </div>
                ))}
              </>
            ) : null}

            {receivedIncome.length ? (
              <>
                <div className="note" style={{ marginTop: 10 }}>
                  Received
                </div>
                {receivedIncome.map((i) => (
                  <div key={i.id} className="note" style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                    <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{i.name}</span>
                    <span>{toDateInputValue(i.date)}</span>
                    <span>{currency(i.amount, state.settings.displayCurrencyCode)}</span>
                  </div>
                ))}
              </>
            ) : null}
          </>
        )}
      </div>

      <div className="field" style={{ marginTop: 16 }}>
        <div className="fieldLabel">Bills</div>
        {dueBills.length === 0 && paidBills.length === 0 ? (
          <div className="note">No bill items for this month.</div>
        ) : (
          <>
            {dueBills.length ? (
              <>
                <div className="note">Due</div>
                {dueBills.map((b) => (
                  <div key={b.id} className="note" style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                    <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{b.name}</span>
                    <span>{toDateInputValue(b.date)}</span>
                    <span>{currency(b.amount, state.settings.displayCurrencyCode)}</span>
                  </div>
                ))}
              </>
            ) : null}

            {paidBills.length ? (
              <>
                <div className="note" style={{ marginTop: 10 }}>
                  Paid
                </div>
                {paidBills.map((b) => (
                  <div key={b.id} className="note" style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                    <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{b.name}</span>
                    <span>{toDateInputValue(b.date)}</span>
                    <span>{currency(b.amount, state.settings.displayCurrencyCode)}</span>
                  </div>
                ))}
              </>
            ) : null}
          </>
        )}
      </div>
    </>
  )
}
