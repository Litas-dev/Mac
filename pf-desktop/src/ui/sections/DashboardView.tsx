import { useEffect, useMemo, useState } from 'react'
import { useAppStore } from '../../app/appStore'
import { setSection } from '../../app/AppProvider'
import { billIsPaidFor, billIsSnoozedActive } from '../../domain/models'
import { currency, goalProgress } from '../../domain/finance'
import { calculateMonthSummary, calculateYearSummary } from '../../domain/reports'
import { visibleTransactions } from '../../domain/people'
import { toDateInputValue } from '../date'
import { expenseCategoryFromSummaryCategory, expenseCategoryFromTransaction, getBudgetAmountForCategory, getBudgetAmountForCustomCategory, normalizeCategoryLabel } from '../../domain/settings'
import { Cell, Pie, PieChart, ResponsiveContainer, Sector, Tooltip } from 'recharts'

const PIE_COLORS = [
  '#0a84ff',
  '#30d158',
  '#ff9f0a',
  '#ff453a',
  '#bf5af2',
  '#5e5ce6',
  '#ff375f',
  '#64d2ff',
  '#ffdb58',
  '#00c7be',
]

export function DashboardView() {
  const { state, dispatch } = useAppStore()
  const now = new Date()
  const [addByGoalId, setAddByGoalId] = useState<Record<string, number>>({})
  const [showExplainNet, setShowExplainNet] = useState(false)
  const [pieMode, setPieMode] = useState<'expenses' | 'income'>('expenses')
  const [pieRange, setPieRange] = useState<'1m' | '3m' | '6m' | '1y'>('1m')
  const [activePieSlice, setActivePieSlice] = useState<number | null>(null)
  const [autoPieIndex, setAutoPieIndex] = useState(0)
  const PieAny: any = Pie

  const tx = useMemo(() => visibleTransactions(state.transactions, state.settings), [state.settings, state.transactions])

  const summary = useMemo(() => {
    const month = new Date(now.getFullYear(), now.getMonth(), 1)
    return calculateMonthSummary({ month, bills: state.bills, incomes: state.incomes, transactions: tx })
  }, [now.getFullYear(), now.getMonth(), state.bills, state.incomes, tx])

  const piePeriod = useMemo(() => {
    const months =
      pieRange === '1m' ? 1 :
      pieRange === '3m' ? 3 :
      pieRange === '6m' ? 6 : 12
    const start = new Date(now.getFullYear(), now.getMonth() - (months - 1), 1)
    const end = new Date(now.getFullYear(), now.getMonth(), 1)
    const label =
      pieRange === '1m' ? 'This Month' :
      pieRange === '3m' ? 'Last 3 Months' :
      pieRange === '6m' ? 'Last 6 Months' : 'Last 12 Months'
    return { start, end, label }
  }, [now.getFullYear(), now.getMonth(), pieRange])

  const pieSummary = useMemo(() => {
    return calculateYearSummary({
      year: piePeriod.start.getFullYear(),
      startMonth: piePeriod.start.getMonth(),
      endYear: piePeriod.end.getFullYear(),
      endMonth: piePeriod.end.getMonth(),
      bills: state.bills,
      incomes: state.incomes,
      transactions: tx,
    })
  }, [piePeriod.end.getFullYear(), piePeriod.end.getMonth(), piePeriod.start.getFullYear(), piePeriod.start.getMonth(), state.bills, state.incomes, tx])

  const pieData = useMemo(() => {
    const map = new Map<string, { name: string; value: number }>()
    if (pieMode === 'income') {
      for (const d of pieSummary.incomeDetails) {
        const key = d.name || d.category?.trim() || 'Income'
        const cur = map.get(key) ?? { name: key, value: 0 }
        map.set(key, { name: cur.name, value: cur.value + d.amount })
      }
    } else {
      for (const d of pieSummary.billDetails) {
        const cat = expenseCategoryFromSummaryCategory(d.category)
        const cur = map.get(cat.key) ?? { name: cat.label, value: 0 }
        map.set(cat.key, { name: cur.name, value: cur.value + d.amount })
      }
    }
    const items = Array.from(map.values())
      .filter((x) => Number.isFinite(x.value) && x.value > 0)
      .sort((a, b) => b.value - a.value)
    return items.slice(0, 10)
  }, [pieMode, pieSummary.billDetails, pieSummary.incomeDetails])

  const pieTotal = useMemo(() => {
    return pieData.reduce((acc, x) => acc + x.value, 0)
  }, [pieData])

  useEffect(() => {
    setAutoPieIndex(0)
  }, [pieMode, pieRange, pieData.length])

  useEffect(() => {
    if (activePieSlice != null) return
    if (pieData.length <= 1) return
    const id = window.setInterval(() => {
      setAutoPieIndex((v) => (v + 1) % pieData.length)
    }, 2600)
    return () => window.clearInterval(id)
  }, [activePieSlice, pieData.length])

  const displayPieIndex = activePieSlice ?? autoPieIndex

  const activePieLabel = useMemo(() => {
    if (pieData.length === 0) return null
    const item = pieData[displayPieIndex]
    if (!item) return null
    const pct = pieTotal > 0 ? Math.round((item.value / pieTotal) * 100) : 0
    return { name: item.name, value: item.value, pct, color: PIE_COLORS[displayPieIndex % PIE_COLORS.length] }
  }, [displayPieIndex, pieData, pieTotal])

  const renderActiveSlice: any = (props: any) => {
    const { cx, cy, innerRadius, outerRadius, startAngle, endAngle, fill } = props
    return (
      <g>
        <Sector cx={cx} cy={cy} innerRadius={innerRadius} outerRadius={outerRadius + 10} startAngle={startAngle} endAngle={endAngle} fill={fill} />
      </g>
    )
  }

  const CustomTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      return (
        <div
          style={{
            background: 'var(--surface)',
            border: '1px solid var(--border)',
            padding: 10,
            borderRadius: 8,
            fontSize: 13,
            boxShadow: 'var(--shadow)',
          }}
        >
          <p style={{ margin: '0 0 6px', fontWeight: 600, color: 'var(--text-h)' }}>{label}</p>
          {payload.map((entry: any) => (
            <p key={entry.name} style={{ color: entry.color, margin: '2px 0' }}>
              {entry.name}: {currency(entry.value, state.settings.displayCurrencyCode)}
            </p>
          ))}
        </div>
      )
    }
    return null
  }

  const goals = useMemo(() => {
    return state.goals.filter((g) => !g.archived).sort((a, b) => a.name.localeCompare(b.name))
  }, [state.goals])

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

  const financialState = useMemo(() => {
    const end30 = forecast.find((f) => f.days === 30)?.end ?? 0
    if (overdue.items.length > 0) {
      return {
        label: 'Risk',
        tone: 'neg' as const,
        detail: `You have overdue bills totaling ${currency(overdue.total, overdue.code)}.`,
      }
    }
    if (end30 < 0) {
      return {
        label: 'Tight',
        tone: 'neutral' as const,
        detail: `Forecast shows ${currency(end30, state.settings.displayCurrencyCode)} over the next 30 days.`,
      }
    }
    return {
      label: 'Stable',
      tone: 'pos' as const,
      detail: `Forecast shows ${currency(end30, state.settings.displayCurrencyCode)} over the next 30 days.`,
    }
  }, [forecast, overdue.code, overdue.items.length, overdue.total, state.settings.displayCurrencyCode])

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

  const dueLaterThisMonth = useMemo(() => {
    const start = new Date(now)
    start.setHours(0, 0, 0, 0)
    const cutoff = new Date(start)
    cutoff.setDate(cutoff.getDate() + 7)
    const endOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0)
    endOfMonth.setHours(23, 59, 59, 999)
    return state.bills
      .filter((b) => {
        if (b.hiddenUntilEdited) return false
        if (billIsSnoozedActive(b, now)) return false
        if (billIsPaidFor(b, b.nextDueDate)) return false
        const d = new Date(b.nextDueDate)
        d.setHours(0, 0, 0, 0)
        return d.getTime() > cutoff.getTime() && d.getTime() <= endOfMonth.getTime()
      })
      .sort((a, b) => a.nextDueDate.getTime() - b.nextDueDate.getTime())
  }, [now, state.bills])

  function sameMonth(a: Date, b: Date): boolean {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth()
  }

  function formatExplainDate(d: Date): string {
    const showYear = d.getFullYear() !== now.getFullYear()
    try {
      const opts: Intl.DateTimeFormatOptions = { month: 'short', day: '2-digit' }
      if (showYear) opts.year = 'numeric'
      return new Intl.DateTimeFormat(undefined, opts).format(d)
    } catch {
      return toDateInputValue(d)
    }
  }

  const budgetMonthDate = useMemo(() => new Date(now.getFullYear(), now.getMonth(), 1), [now.getFullYear(), now.getMonth()])

  const budgetRows = useMemo(() => {
    const spentByKey = new Map<string, number>()
    for (const t of tx) {
      if (t.kind !== 'expense') continue
      if (!sameMonth(t.date, budgetMonthDate)) continue
      const cat = expenseCategoryFromTransaction(t)
      spentByKey.set(cat.key, (spentByKey.get(cat.key) ?? 0) + t.amount.value)
    }

    const builtin: Array<'housing' | 'utilities' | 'subscriptions' | 'insurance' | 'taxes' | 'transport' | 'other'> = [
      'housing',
      'utilities',
      'subscriptions',
      'insurance',
      'taxes',
      'transport',
      'other',
    ]
    const customLabels = Array.isArray(state.settings.budgetCategories) ? state.settings.budgetCategories : []

    const rows: Array<{ key: string; label: string; assigned: number; spent: number; left: number }> = []

    for (const c of builtin) {
      const key = `builtin:${c}`
      const assigned = getBudgetAmountForCategory(state.settings, key)
      const spent = spentByKey.get(key) ?? 0
      rows.push({ key, label: c.charAt(0).toUpperCase() + c.slice(1), assigned, spent, left: assigned - spent })
    }

    for (const raw of customLabels) {
      const label = normalizeCategoryLabel(raw)
      if (!label) continue
      const key = `custom:${label}`
      const assigned = getBudgetAmountForCustomCategory(state.settings, label)
      const spent = spentByKey.get(`custom:${label.toLowerCase()}`) ?? 0
      rows.push({ key, label, assigned, spent, left: assigned - spent })
    }

    return rows
      .filter((r) => Math.abs(r.assigned) > 0 || Math.abs(r.spent) > 0)
      .sort((a, b) => Math.abs(b.assigned) - Math.abs(a.assigned))
  }, [budgetMonthDate, state.settings, tx])

  const budgetTotals = useMemo(() => {
    return budgetRows.reduce(
      (acc, r) => ({ assigned: acc.assigned + r.assigned, spent: acc.spent + r.spent, left: acc.left + r.left }),
      { assigned: 0, spent: 0, left: 0 }
    )
  }, [budgetRows])

  const budgetPct = useMemo(() => {
    const { assigned, spent } = budgetTotals
    if (assigned > 0) return Math.min(1, Math.max(0, spent / assigned))
    if (spent > 0) return 1
    return 0
  }, [budgetTotals])

  function openBill(id: string) {
    dispatch({ type: 'ui/selectBill', id })
    dispatch(setSection('bills'))
  }

  function openBudget() {
    dispatch(setSection('budget'))
  }

  function markPaid(id: string) {
    const bill = state.bills.find((b) => b.id === id)
    if (!bill) return
    dispatch({ type: 'bills/logPayment', id, date: bill.nextDueDate })
  }

  function applyAddToGoalSaved(goalId: string) {
    const g = state.goals.find((x) => x.id === goalId)
    if (!g) return
    const addAmount = addByGoalId[goalId] ?? 0
    if (!Number.isFinite(addAmount) || addAmount === 0) return
    dispatch({
      type: 'goals/update',
      goal: { ...g, savedAmount: { ...g.savedAmount, value: g.savedAmount.value + addAmount } },
    })
    setAddByGoalId((prev) => ({ ...prev, [goalId]: 0 }))
  }

  const goalsSection =
    goals.length > 0 ? (
      <div className="dashSection">
        <div className="dashSectionHeader">
          <div className="dashSectionTitle">Goals</div>
          <div className="dashSectionChevron">▾</div>
        </div>

        <div className="list" style={{ marginTop: 12 }}>
          {goals.map((g) => {
            const p = goalProgress(g.savedAmount.value, g.targetAmount.value)
            const pct = Math.round(p * 100)
            return (
              <div key={g.id} className="listItem" style={{ borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
                <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 10 }}>
                  <div
                    style={{
                      minWidth: 0,
                      fontSize: 13,
                      fontWeight: 700,
                      color: 'var(--text-h)',
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      whiteSpace: 'nowrap',
                    }}
                  >
                    {g.name || 'Untitled'}
                  </div>
                  <div
                    style={{
                      flex: 'none',
                      fontSize: 12,
                      fontWeight: 800,
                      fontVariantNumeric: 'tabular-nums',
                      color: 'var(--text-h)',
                    }}
                  >
                    {pct}%
                  </div>
                </div>

                <div style={{ marginTop: 6, fontSize: 12, color: 'var(--muted)' }}>
                  {currency(g.savedAmount.value, g.savedAmount.currencyCode)} / {currency(g.targetAmount.value, g.targetAmount.currencyCode)}
                </div>

                <div className="progressRow" style={{ marginTop: 8 }}>
                  <div className="progressBar">
                    <div className="progressFill" style={{ width: `${Math.min(100, Math.max(0, p * 100))}%` }} />
                  </div>
                  <div className="progressValue">{pct}%</div>
                </div>

                <div className="form" style={{ marginTop: 10 }}>
                  <div className="fieldRow" style={{ gridTemplateColumns: 'minmax(0, 1fr) auto' }}>
                    <input
                      type="number"
                      value={addByGoalId[g.id] ?? 0}
                      onChange={(e) => setAddByGoalId((prev) => ({ ...prev, [g.id]: Number(e.target.value) }))}
                    />
                    <button
                      type="button"
                      onClick={() => applyAddToGoalSaved(g.id)}
                      disabled={!Number.isFinite(addByGoalId[g.id] ?? 0) || (addByGoalId[g.id] ?? 0) === 0}
                      style={{ padding: '8px 10px' }}
                    >
                      Add
                    </button>
                  </div>
                </div>
              </div>
            )
          })}
        </div>
      </div>
    ) : null

  const pieSection = goals.length > 0 ? (
    <div className="dashSection">
      <div className="dashSectionHeader">
        <div className="dashSectionTitle">{piePeriod.label}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div className="segmented" style={{ height: 30 }}>
            <button type="button" className={pieRange === '1m' ? 'active' : ''} onClick={() => setPieRange('1m')}>
              1M
            </button>
            <button type="button" className={pieRange === '3m' ? 'active' : ''} onClick={() => setPieRange('3m')}>
              3M
            </button>
            <button type="button" className={pieRange === '6m' ? 'active' : ''} onClick={() => setPieRange('6m')}>
              6M
            </button>
            <button type="button" className={pieRange === '1y' ? 'active' : ''} onClick={() => setPieRange('1y')}>
              1Y
            </button>
          </div>
          <div className="segmented" style={{ height: 30 }}>
            <button type="button" className={pieMode === 'expenses' ? 'active' : ''} onClick={() => setPieMode('expenses')}>
              Expenses
            </button>
            <button type="button" className={pieMode === 'income' ? 'active' : ''} onClick={() => setPieMode('income')}>
              Income
            </button>
          </div>
        </div>
      </div>

      <div style={{ marginTop: 12 }}>
        {pieData.length > 0 ? (
          <>
            <div style={{ width: '100%', height: 180 }}>
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <PieAny
                    data={pieData}
                    dataKey="value"
                    nameKey="name"
                    cx="50%"
                    cy="50%"
                    outerRadius={78}
                    paddingAngle={2}
                    stroke="var(--surface)"
                    strokeWidth={1}
                    activeIndex={activePieSlice ?? undefined}
                    activeShape={renderActiveSlice}
                    onMouseEnter={(_: any, idx: number) => setActivePieSlice(idx)}
                    onMouseLeave={() => setActivePieSlice(null)}
                  >
                    {pieData.map((_, index) => (
                      <Cell key={`cell-${index}`} fill={PIE_COLORS[index % PIE_COLORS.length]} style={{ outline: 'none' }} />
                    ))}
                  </PieAny>
                  <Tooltip content={<CustomTooltip />} />
                </PieChart>
              </ResponsiveContainer>
            </div>
            <div className="dashPieInfo" aria-live="polite">
              {activePieLabel ? (
                <div key={`${displayPieIndex}:${activePieLabel.name}`} className="dashPieInfoInner">
                  <div className="dashPieInfoLeft">
                    <span className="dashPieDot" style={{ background: activePieLabel.color }} />
                    <div className="dashPieName">{activePieLabel.name}</div>
                  </div>
                  <div className="dashPieInfoRight">
                    <span className="dashPieAmount">{currency(activePieLabel.value, state.settings.displayCurrencyCode)}</span>
                    <span className="pill" data-tone="neutral">{activePieLabel.pct}%</span>
                  </div>
                </div>
              ) : (
                <div className="dashPieInfoInner">
                  <div className="dashPieName">Hover a slice to see details</div>
                </div>
              )}
            </div>
            <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', marginTop: 10 }}>
              {pieData.slice(0, 6).map((it, idx) => {
                const pct = pieTotal > 0 ? Math.round((it.value / pieTotal) * 100) : 0
                return (
                  <span key={it.name} className="pill" data-tone="neutral" style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
                    <span style={{ width: 8, height: 8, borderRadius: 999, background: PIE_COLORS[idx % PIE_COLORS.length] }} />
                    <span style={{ maxWidth: 160, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{it.name}</span>
                    <span style={{ opacity: 0.8 }}>{pct}%</span>
                  </span>
                )
              })}
            </div>
            <div className="note" style={{ marginTop: 6 }}>
              Total: {currency(pieTotal, state.settings.displayCurrencyCode)}
            </div>
          </>
        ) : (
          <div className="note">No {pieMode === 'income' ? 'income' : 'expenses'} data for this period.</div>
        )}
      </div>
    </div>
  ) : null

  useEffect(() => {
    if (!showExplainNet) return
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setShowExplainNet(false)
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [showExplainNet])

  const explainNetModal = showExplainNet ? (
    <div className="modalBackdrop" role="dialog" aria-modal="true" aria-label="Left after bills breakdown" onClick={() => setShowExplainNet(false)}>
      <div
        className="modal reconcileModal"
        style={{ width: 'min(920px, calc(100vw - 40px))', maxHeight: 'min(78vh, 720px)', overflowY: 'auto' }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
          <div style={{ minWidth: 0 }}>
            <div className="modalTitle">Left After Bills — Breakdown</div>
            <div className="muted" style={{ fontSize: 12 }}>
              Explains what’s included in “Income”, “Bills”, and “Left After Bills” for this month.
            </div>
          </div>
          <button type="button" onClick={() => setShowExplainNet(false)} style={{ padding: '6px 10px', fontSize: 12, fontWeight: 700 }}>
            Close
          </button>
        </div>

        <div className="note" style={{ marginTop: 12 }}>
          Totals include: income receipts + upcoming income pay dates (not yet received) + imported income transactions; and bill payments + unpaid bills due this month + imported expense transactions.
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 1fr)', gap: 12, marginTop: 12 }}>
          <div className="list" style={{ marginTop: 0 }}>
            <div className="dashExplainHeader">
              Income total: {currency(summary.income, state.settings.displayCurrencyCode)}
            </div>
            {summary.incomeDetails.map((d) => (
              <div key={d.id} className="dashExplainRow">
                <div className="dashExplainMain">
                  <div className="dashExplainTitleRow">
                    <div className="dashExplainName">{d.name || 'Income'}</div>
                    <div className="dashExplainChips">
                      <span className="pill" data-tone="neutral">
                        {formatExplainDate(d.date)}
                      </span>
                      <span className="pill" data-tone={d.isPaid ? 'pos' : 'neutral'}>
                        {d.isPaid ? 'Received' : 'Expected'}
                      </span>
                    </div>
                  </div>
                  {d.category ? <div className="dashExplainMeta">{d.category}</div> : null}
                </div>
                <div className="dashExplainAmount">{currency(d.amount, state.settings.displayCurrencyCode)}</div>
              </div>
            ))}
            {summary.incomeDetails.length === 0 ? <div className="note" style={{ marginTop: 0, padding: '10px 12px' }}>No income items counted.</div> : null}
          </div>

          <div className="list" style={{ marginTop: 0 }}>
            <div className="dashExplainHeader">
              Bills/expenses total: {currency(summary.bills, state.settings.displayCurrencyCode)}
            </div>
            {summary.billDetails.map((d) => (
              <div key={d.id} className="dashExplainRow">
                <div className="dashExplainMain">
                  <div className="dashExplainTitleRow">
                    <div className="dashExplainName">{d.name || 'Bill'}</div>
                    <div className="dashExplainChips">
                      <span className="pill" data-tone="neutral">
                        {formatExplainDate(d.date)}
                      </span>
                      <span className="pill" data-tone={d.isPaid ? 'pos' : 'neg'}>
                        {d.isPaid ? 'Paid' : 'Due'}
                      </span>
                    </div>
                  </div>
                  {d.category ? <div className="dashExplainMeta">{d.category}</div> : null}
                </div>
                <div className="dashExplainAmount">{currency(d.amount, state.settings.displayCurrencyCode)}</div>
              </div>
            ))}
            {summary.billDetails.length === 0 ? <div className="note" style={{ marginTop: 0, padding: '10px 12px' }}>No bills/expenses counted.</div> : null}
          </div>
        </div>
      </div>
    </div>
  ) : null

  const billsDueSection = (
    <div className="dashSection">
      <div className="dashSectionHeader">
        <div className="dashSectionTitle">Bills Due</div>
        <div className="dashSectionChevron">▾</div>
      </div>

      {overdue.items.length === 0 && dueNext7.length === 0 && dueLaterThisMonth.length === 0 ? (
        <div className="note" style={{ marginTop: 12 }}>
          All paid.
        </div>
      ) : (
        <div className="list" style={{ marginTop: 12 }}>
          {overdue.items.map((b) => (
            <div
              key={b.id}
              className="note"
              style={{
                display: 'grid',
                gridTemplateColumns: '1fr auto auto',
                gap: 8,
                padding: '10px 12px',
                borderBottom: '1px solid rgba(255,255,255,0.06)',
              }}
            >
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
            <div
              key={b.id}
              className="note"
              style={{
                display: 'grid',
                gridTemplateColumns: '1fr auto auto',
                gap: 8,
                padding: '10px 12px',
                borderBottom: '1px solid rgba(255,255,255,0.06)',
              }}
            >
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

          {dueLaterThisMonth.length > 0 ? (
            <div className="note" style={{ marginTop: 0, padding: '10px 12px', borderBottom: '1px solid rgba(255,255,255,0.06)', fontWeight: 700 }}>
              Bills to pay this month ({dueLaterThisMonth.length})
            </div>
          ) : null}
          {dueLaterThisMonth.map((b) => (
            <div
              key={b.id}
              className="note"
              style={{
                display: 'grid',
                gridTemplateColumns: '1fr auto auto',
                gap: 8,
                padding: '10px 12px',
                borderBottom: '1px solid rgba(255,255,255,0.06)',
              }}
            >
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
  )

  const budgetSection = (
    <div className="dashSection">
      <div className="dashSectionHeader">
        <div className="dashSectionTitle">Budget</div>
        <button type="button" onClick={openBudget} style={{ padding: '2px 8px' }}>
          Open
        </button>
      </div>

      {budgetRows.length === 0 ? (
        <div className="note" style={{ marginTop: 12 }}>
          No budget set for this month. Add budgets in the Budget screen.
        </div>
      ) : (
        <>
          <div style={{ display: 'flex', gap: 10, alignItems: 'center', flexWrap: 'wrap', marginTop: 12 }}>
            <span className="pill" data-tone="neutral">Budget {currency(budgetTotals.assigned, state.settings.displayCurrencyCode)}</span>
            <span className="pill" data-tone="neutral">Spent {currency(budgetTotals.spent, state.settings.displayCurrencyCode)}</span>
            <span className="pill" data-tone={budgetTotals.left > 0 ? 'pos' : budgetTotals.left < 0 ? 'neg' : 'neutral'}>
              Left {currency(budgetTotals.left, state.settings.displayCurrencyCode)}
            </span>
          </div>

          <div className="progressRow" style={{ marginTop: 10 }}>
            <div className="progressBar">
              <div
                className="progressFill"
                style={{
                  width: `${Math.round(budgetPct * 100)}%`,
                  background: budgetTotals.assigned > 0 && budgetTotals.spent > budgetTotals.assigned ? 'var(--red)' : 'var(--accent)',
                }}
              />
            </div>
            <div className="progressValue">{Math.round(budgetPct * 100)}%</div>
          </div>

          <div className="list" style={{ marginTop: 12, maxHeight: 240, overflowY: 'auto' }}>
            {budgetRows.map((r) => {
              const pct = r.assigned > 0 ? Math.min(1, Math.max(0, r.spent / r.assigned)) : r.spent > 0 ? 1 : 0
              const tone: 'pos' | 'neg' | 'neutral' = r.left > 0 ? 'pos' : r.left < 0 ? 'neg' : 'neutral'
              const fill = r.assigned > 0 && r.spent > r.assigned ? 'var(--red)' : 'var(--accent)'
              return (
                <div key={r.key} className="note" style={{ marginTop: 0, padding: '10px 12px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
                  <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0, 1fr) auto', gap: 10, alignItems: 'center' }}>
                    <div style={{ minWidth: 0 }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10 }}>
                        <div style={{ fontWeight: 800, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', color: 'var(--text-h)' }}>
                          {r.label}
                        </div>
                        <div style={{ fontSize: 12, color: 'var(--muted)', fontVariantNumeric: 'tabular-nums' }}>
                          {currency(r.spent, state.settings.displayCurrencyCode)} / {currency(r.assigned, state.settings.displayCurrencyCode)}
                        </div>
                      </div>
                      <div className="progressRow" style={{ marginTop: 8 }}>
                        <div className="progressBar">
                          <div className="progressFill" style={{ width: `${Math.round(pct * 100)}%`, background: fill }} />
                        </div>
                        <div className="progressValue">{Math.round(pct * 100)}%</div>
                      </div>
                    </div>
                    <div style={{ textAlign: 'right' }}>
                      <span className="pill" data-tone={tone}>{currency(r.left, state.settings.displayCurrencyCode)}</span>
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
        </>
      )}
    </div>
  )

  return (
    <>
      <div className="dashBanner" data-tone={financialState.tone}>
        <div className="dashBannerDot" />
        <div style={{ minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {financialState.label}: {financialState.detail}
        </div>
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
          <button
            type="button"
            onClick={() => setShowExplainNet((v) => !v)}
            style={{
              marginTop: 8,
              width: '100%',
              padding: '6px 10px',
              fontSize: 12,
              fontWeight: 700,
            }}
          >
            Explain
          </button>
        </div>
        <div className="dashKpi">
          <div className="dashKpiLabel">Next Bill</div>
          <div className="dashKpiValue" style={{ fontSize: 13, fontWeight: 700 }}>
            {nextBill ? nextBill.name : 'None'}
          </div>
        </div>
      </div>

      {explainNetModal}

      {goalsSection ? (
        <div className="dashTwoCol">
          <div className="dashStack">
            {billsDueSection}
            {budgetSection}
          </div>
          <div className="dashStack">
            {pieSection}
            {goalsSection}
          </div>
        </div>
      ) : (
        <div className="dashStack">
          {billsDueSection}
          {budgetSection}
        </div>
      )}
    </>
  )
}
