import { useMemo, useState, useEffect } from 'react'
import { useAppStore } from '../../app/appStore'
import { currency } from '../../domain/finance'
import { calculateMonthSummary, calculateYearSummary } from '../../domain/reports'
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  Sector,
} from 'recharts'

const COLORS = [
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

export function ReportsView() {
  const { state } = useAppStore()
  const PieAny: any = Pie
  const [yearStr, setYearStr] = useState(() => {
    return String(new Date().getFullYear())
  })
  const [startMonthStr, setStartMonthStr] = useState('0')
  const [selectedMonthIndex, setSelectedMonthIndex] = useState<number | null>(null)
  const [activeIncomeSlice, setActiveIncomeSlice] = useState<number | null>(null)
  const [activeExpenseSlice, setActiveExpenseSlice] = useState<number | null>(null)
  const [showIncomePie, setShowIncomePie] = useState(true)
  const [showExpensePie, setShowExpensePie] = useState(true)

  const selectedYear = useMemo(() => {
    const y = Number(yearStr)
    return Number.isFinite(y) ? y : new Date().getFullYear()
  }, [yearStr])

  const selectedStartMonth = useMemo(() => {
    const m = Number(startMonthStr)
    return Number.isFinite(m) ? m : 0
  }, [startMonthStr])

  useEffect(() => {
    setSelectedMonthIndex(null)
  }, [selectedYear, selectedStartMonth])

  const yearSummary = useMemo(() => {
    return calculateYearSummary({
      year: selectedYear,
      startMonth: selectedStartMonth,
      bills: state.bills,
      incomes: state.incomes,
      transactions: state.transactions,
    })
  }, [selectedYear, selectedStartMonth, state.bills, state.incomes, state.transactions])

  const selectedMonthSummary = useMemo(() => {
    if (selectedMonthIndex === null) return null
    return calculateMonthSummary({
      month: new Date(selectedYear, selectedStartMonth + selectedMonthIndex, 1),
      bills: state.bills,
      incomes: state.incomes,
      transactions: state.transactions,
    })
  }, [selectedYear, selectedStartMonth, selectedMonthIndex, state.bills, state.incomes, state.transactions])

  const chartData = useMemo(() => {
    if (yearSummary) {
      return yearSummary.months.map((m) => ({
        name: m.monthName,
        index: m.arrayIndex,
        Income: m.income,
        Expenses: m.bills,
        Net: m.net,
      }))
    }
    return []
  }, [yearSummary])

  const pieData = useMemo(() => {
    const details = selectedMonthIndex !== null ? selectedMonthSummary?.billDetails : yearSummary?.billDetails
    if (!details) return []
    const map = new Map<string, number>()
    for (const b of details) {
      const cat = b.category || 'other'
      const name = cat.charAt(0).toUpperCase() + cat.slice(1)
      map.set(name, (map.get(name) ?? 0) + b.amount)
    }
    return Array.from(map.entries())
      .map(([name, value]) => ({ name, value }))
      .filter((x) => x.value > 0)
      .sort((a, b) => b.value - a.value)
  }, [selectedMonthIndex, selectedMonthSummary, yearSummary])

  const incomePieData = useMemo(() => {
    const details = selectedMonthIndex !== null ? selectedMonthSummary?.incomeDetails : yearSummary?.incomeDetails
    if (!details) return []
    const map = new Map<string, number>()
    for (const i of details) {
      const name = (i.name || 'Income').trim() || 'Income'
      map.set(name, (map.get(name) ?? 0) + i.amount)
    }
    return Array.from(map.entries())
      .map(([name, value]) => ({ name, value }))
      .filter((x) => x.value > 0)
      .sort((a, b) => b.value - a.value)
  }, [selectedMonthIndex, selectedMonthSummary, yearSummary])

  const incomePieTotal = useMemo(() => incomePieData.reduce((acc, x) => acc + x.value, 0), [incomePieData])
  const expensePieTotal = useMemo(() => pieData.reduce((acc, x) => acc + x.value, 0), [pieData])

  const renderActiveSlice: any = (props: any) => {
    const RADIAN = Math.PI / 180
    const { cx, cy, midAngle, innerRadius, outerRadius, startAngle, endAngle, fill, payload, value, percent } = props
    const sin = Math.sin(-RADIAN * midAngle)
    const cos = Math.cos(-RADIAN * midAngle)
    const sx = cx + (outerRadius + 6) * cos
    const sy = cy + (outerRadius + 6) * sin
    const mx = cx + (outerRadius + 18) * cos
    const my = cy + (outerRadius + 18) * sin
    const ex = mx + (cos >= 0 ? 1 : -1) * 14
    const ey = my
    const textAnchor = cos >= 0 ? 'start' : 'end'
    const label = `${payload?.name ?? ''} • ${currency(value, state.settings.displayCurrencyCode)} • ${(((percent || 0) * 100) as number).toFixed(1)}%`

    return (
      <g>
        <Sector cx={cx} cy={cy} innerRadius={innerRadius} outerRadius={outerRadius + 8} startAngle={startAngle} endAngle={endAngle} fill={fill} />
        <Sector
          cx={cx}
          cy={cy}
          innerRadius={outerRadius + 10}
          outerRadius={outerRadius + 12}
          startAngle={startAngle}
          endAngle={endAngle}
          fill={fill}
          fillOpacity={0.35}
        />
        <path d={`M${sx},${sy}L${mx},${my}L${ex},${ey}`} stroke={fill} fill="none" />
        <circle cx={ex} cy={ey} r={2} fill={fill} stroke="none" />
        <text x={ex + (cos >= 0 ? 6 : -6)} y={ey} textAnchor={textAnchor} fill="var(--text-h)" fontSize={12} dominantBaseline="central">
          {label}
        </text>
      </g>
    )
  }

  const CustomTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      return (
        <div style={{ background: 'var(--surface)', border: '1px solid var(--border)', padding: 10, borderRadius: 8, fontSize: 13, boxShadow: 'var(--shadow)' }}>
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

  function renderYearly() {
    if (!yearSummary) return null

    const displayIncome = selectedMonthIndex !== null ? selectedMonthSummary?.income || 0 : yearSummary.income
    const displayBills = selectedMonthIndex !== null ? selectedMonthSummary?.bills || 0 : yearSummary.bills
    const displayNet = selectedMonthIndex !== null ? selectedMonthSummary?.net || 0 : yearSummary.net

    return (
      <>
        <div className="grid" style={{ marginTop: 12 }}>
          <div className="card">
            <div className="cardLabel">{selectedMonthIndex !== null ? `${yearSummary.months[selectedMonthIndex]?.monthName} Income` : 'Total Income'}</div>
            <div className="cardValue">{currency(displayIncome, state.settings.displayCurrencyCode)}</div>
          </div>
          <div className="card">
            <div className="cardLabel">{selectedMonthIndex !== null ? `${yearSummary.months[selectedMonthIndex]?.monthName} Expenses` : 'Total Expenses'}</div>
            <div className="cardValue">{currency(displayBills, state.settings.displayCurrencyCode)}</div>
          </div>
          <div className="card">
            <div className="cardLabel">{selectedMonthIndex !== null ? `${yearSummary.months[selectedMonthIndex]?.monthName} Net` : 'Total Net'}</div>
            <div className="cardValue">{currency(displayNet, state.settings.displayCurrencyCode)}</div>
          </div>
        </div>

        <div className="groupBox" style={{ marginTop: 16 }}>
          <div className="groupTitle">Cash Flow</div>
          {selectedMonthIndex !== null ? (
            <div className="note" style={{ marginTop: 6, display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12 }}>
              <span>Selected month: {yearSummary.months[selectedMonthIndex]?.monthName}</span>
              <button type="button" onClick={() => setSelectedMonthIndex(null)} style={{ padding: '4px 10px', fontSize: 12 }}>
                Clear
              </button>
            </div>
          ) : (
            <div className="note" style={{ marginTop: 6 }}>
              Click a month to focus the pies and totals.
            </div>
          )}
          <div style={{ width: '100%', height: 160, marginTop: 10 }}>
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={chartData} margin={{ top: 0, right: 0, left: 0, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border-2)" vertical={false} />
                <XAxis dataKey="name" stroke="var(--muted)" fontSize={11} tickLine={false} axisLine={false} dy={6} />
                <YAxis stroke="var(--muted)" fontSize={11} tickLine={false} axisLine={false} tickFormatter={(v) => `$${(v/1000).toFixed(0)}k`} width={42} />
                <Tooltip content={<CustomTooltip />} cursor={{ fill: 'var(--hover-2)' }} />
                <Legend iconType="circle" wrapperStyle={{ fontSize: 11, paddingTop: 4 }} />
                <Bar
                  dataKey="Income"
                  fill="#30d158"
                  radius={[4, 4, 0, 0]}
                  maxBarSize={28}
                  style={{ cursor: 'pointer' }}
                  onClick={(data: any) => {
                    const idx = data?.payload?.index
                    if (typeof idx !== 'number') return
                    setSelectedMonthIndex((cur) => (cur === idx ? null : idx))
                  }}
                >
                  {chartData.map((_, index) => (
                    <Cell key={`cell-${index}`} fill={selectedMonthIndex === index ? '#34c759' : '#30d158'} fillOpacity={selectedMonthIndex === null || selectedMonthIndex === index ? 1 : 0.4} />
                  ))}
                </Bar>
                <Bar
                  dataKey="Expenses"
                  fill="#ff453a"
                  radius={[4, 4, 0, 0]}
                  maxBarSize={28}
                  style={{ cursor: 'pointer' }}
                  onClick={(data: any) => {
                    const idx = data?.payload?.index
                    if (typeof idx !== 'number') return
                    setSelectedMonthIndex((cur) => (cur === idx ? null : idx))
                  }}
                >
                  {chartData.map((_, index) => (
                    <Cell key={`cell-${index}`} fill={selectedMonthIndex === index ? '#ff3b30' : '#ff453a'} fillOpacity={selectedMonthIndex === null || selectedMonthIndex === index ? 1 : 0.4} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>

        {pieData.length > 0 || incomePieData.length > 0 ? (
          <>
            <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap', marginTop: 16 }}>
            {showIncomePie && incomePieData.length > 0 ? (
              <div className="groupBox" style={{ flex: '1 1 360px' }}>
                <div className="groupTitle">
                  {selectedMonthIndex !== null ? `Income by Source (${yearSummary.months[selectedMonthIndex]?.monthName})` : 'Income by Source (Total)'}
                </div>
                <div className="note" style={{ marginTop: 6 }}>
                  Total: {currency(incomePieTotal, state.settings.displayCurrencyCode)} • Sources: {incomePieData.length}
                </div>
                <div style={{ display: 'flex', gap: 10, alignItems: 'stretch', marginTop: 10 }}>
                  <div style={{ flex: '0 0 320px', height: 280 }}>
                    <ResponsiveContainer width="100%" height="100%">
                      <PieChart>
                        <PieAny
                          data={incomePieData}
                          dataKey="value"
                          nameKey="name"
                          cx="50%"
                          cy="50%"
                          outerRadius={100}
                          paddingAngle={2}
                          stroke="var(--surface)"
                          strokeWidth={1}
                          activeIndex={activeIncomeSlice ?? undefined}
                          activeShape={renderActiveSlice}
                          onMouseEnter={(_: any, idx: number) => setActiveIncomeSlice(idx)}
                          onMouseLeave={() => setActiveIncomeSlice(null)}
                        >
                          {incomePieData.map((_, index) => (
                            <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} style={{ outline: 'none' }} />
                          ))}
                        </PieAny>
                        <Tooltip content={<CustomTooltip />} />
                      </PieChart>
                    </ResponsiveContainer>
                  </div>
                  <div style={{ flex: '1 1 auto', minWidth: 200, maxHeight: 280, overflowY: 'auto', paddingRight: 6 }}>
                    {incomePieData.map((x, idx) => {
                      const pct = incomePieTotal > 0 ? (x.value / incomePieTotal) * 100 : 0
                      const active = activeIncomeSlice === idx
                      return (
                        <button
                          key={x.name}
                          type="button"
                          onMouseEnter={() => setActiveIncomeSlice(idx)}
                          onMouseLeave={() => setActiveIncomeSlice(null)}
                          onClick={() => setActiveIncomeSlice((cur) => (cur === idx ? null : idx))}
                          style={{
                            width: '100%',
                            display: 'flex',
                            justifyContent: 'space-between',
                            gap: 10,
                            padding: '6px 8px',
                            borderRadius: 8,
                            border: active ? '1px solid var(--border)' : '1px solid transparent',
                            background: active ? 'var(--hover-2)' : 'transparent',
                            cursor: 'pointer',
                            textAlign: 'left',
                            color: 'inherit',
                          }}
                        >
                          <span style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
                            <span style={{ width: 10, height: 10, borderRadius: 3, background: COLORS[idx % COLORS.length], flex: '0 0 auto' }} />
                            <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{x.name}</span>
                          </span>
                          <span style={{ flex: '0 0 auto', opacity: 0.85, fontVariantNumeric: 'tabular-nums' }}>
                            {pct.toFixed(1)}% • {currency(x.value, state.settings.displayCurrencyCode)}
                          </span>
                        </button>
                      )
                    })}
                  </div>
                </div>
              </div>
            ) : null}

            {showExpensePie && pieData.length > 0 ? (
              <div className="groupBox" style={{ flex: '1 1 360px' }}>
                <div className="groupTitle">
                  {selectedMonthIndex !== null ? `Expenses by Category (${yearSummary.months[selectedMonthIndex]?.monthName})` : 'Expenses by Category (Total)'}
                </div>
                <div className="note" style={{ marginTop: 6 }}>
                  Total: {currency(expensePieTotal, state.settings.displayCurrencyCode)} • Categories: {pieData.length}
                </div>
                <div style={{ display: 'flex', gap: 10, alignItems: 'stretch', marginTop: 10 }}>
                  <div style={{ flex: '0 0 320px', height: 280 }}>
                    <ResponsiveContainer width="100%" height="100%">
                      <PieChart>
                        <PieAny
                          data={pieData}
                          dataKey="value"
                          nameKey="name"
                          cx="50%"
                          cy="50%"
                          outerRadius={100}
                          paddingAngle={2}
                          stroke="var(--surface)"
                          strokeWidth={1}
                          activeIndex={activeExpenseSlice ?? undefined}
                          activeShape={renderActiveSlice}
                          onMouseEnter={(_: any, idx: number) => setActiveExpenseSlice(idx)}
                          onMouseLeave={() => setActiveExpenseSlice(null)}
                        >
                          {pieData.map((_, index) => (
                            <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} style={{ outline: 'none' }} />
                          ))}
                        </PieAny>
                        <Tooltip content={<CustomTooltip />} />
                      </PieChart>
                    </ResponsiveContainer>
                  </div>
                  <div style={{ flex: '1 1 auto', minWidth: 200, maxHeight: 280, overflowY: 'auto', paddingRight: 6 }}>
                    {pieData.map((x, idx) => {
                      const pct = expensePieTotal > 0 ? (x.value / expensePieTotal) * 100 : 0
                      const active = activeExpenseSlice === idx
                      return (
                        <button
                          key={x.name}
                          type="button"
                          onMouseEnter={() => setActiveExpenseSlice(idx)}
                          onMouseLeave={() => setActiveExpenseSlice(null)}
                          onClick={() => setActiveExpenseSlice((cur) => (cur === idx ? null : idx))}
                          style={{
                            width: '100%',
                            display: 'flex',
                            justifyContent: 'space-between',
                            gap: 10,
                            padding: '6px 8px',
                            borderRadius: 8,
                            border: active ? '1px solid var(--border)' : '1px solid transparent',
                            background: active ? 'var(--hover-2)' : 'transparent',
                            cursor: 'pointer',
                            textAlign: 'left',
                            color: 'inherit',
                          }}
                        >
                          <span style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
                            <span style={{ width: 10, height: 10, borderRadius: 3, background: COLORS[idx % COLORS.length], flex: '0 0 auto' }} />
                            <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{x.name}</span>
                          </span>
                          <span style={{ flex: '0 0 auto', opacity: 0.85, fontVariantNumeric: 'tabular-nums' }}>
                            {pct.toFixed(1)}% • {currency(x.value, state.settings.displayCurrencyCode)}
                          </span>
                        </button>
                      )
                    })}
                  </div>
                </div>
              </div>
            ) : null}
            </div>
          </>
        ) : null}
      </>
    )
  }

  return (
    <>
      <div className="row" style={{ marginTop: 8 }}>
        <div className="rowActions">
          <label className="field" style={{ margin: 0, marginRight: 16 }}>
            <div className="fieldLabel">Start Month</div>
            <select value={startMonthStr} onChange={(e) => setStartMonthStr(e.target.value)} style={{ width: 120, height: 32 }}>
              <option value="0">January</option>
              <option value="1">February</option>
              <option value="2">March</option>
              <option value="3">April</option>
              <option value="4">May</option>
              <option value="5">June</option>
              <option value="6">July</option>
              <option value="7">August</option>
              <option value="8">September</option>
              <option value="9">October</option>
              <option value="10">November</option>
              <option value="11">December</option>
            </select>
          </label>
          <label className="field" style={{ margin: 0 }}>
            <div className="fieldLabel">Year</div>
            <input type="number" value={yearStr} onChange={(e) => setYearStr(e.target.value)} style={{ width: 100, height: 32 }} min={1900} max={2100} />
          </label>
          <label className="check" style={{ margin: 0, marginLeft: 16 }}>
            <input type="checkbox" checked={showIncomePie} onChange={(e) => setShowIncomePie(e.target.checked)} />
            Income pie
          </label>
          <label className="check" style={{ margin: 0 }}>
            <input type="checkbox" checked={showExpensePie} onChange={(e) => setShowExpensePie(e.target.checked)} />
            Expenses pie
          </label>
        </div>
      </div>

      {renderYearly()}
    </>
  )
}
