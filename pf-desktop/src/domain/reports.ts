import type { Bill, Income } from './models'
import { billIsPaidFor } from './models'

export interface SummaryItem {
  id: string
  name: string
  amount: number
  date: Date
  isPaid: boolean
  billId?: string | null
  incomeId?: string | null
}

export interface MonthSummary {
  income: number
  bills: number
  net: number
  incomeDetails: SummaryItem[]
  billDetails: SummaryItem[]
}

export function calculateMonthSummary(params: { month: Date; bills: Bill[]; incomes: Income[] }): MonthSummary {
  const month = params.month
  const bills = params.bills
  const incomes = params.incomes

  let incomeTotal = 0
  let billTotal = 0
  const incomeDetails: SummaryItem[] = []
  const billDetails: SummaryItem[] = []

  const sameMonth = (a: Date, b: Date) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth()
  const sameDay = (a: Date, b: Date) =>
    a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()

  for (const inc of incomes) {
    for (const p of inc.receipts ?? []) {
      if (sameMonth(p.date, month)) {
        incomeTotal += p.amount.value
        incomeDetails.push({
          id: crypto.randomUUID(),
          name: inc.name,
          amount: p.amount.value,
          date: p.date,
          isPaid: true,
          incomeId: inc.id,
        })
      }
    }
    if (sameMonth(inc.nextPayDate, month)) {
      const already = (inc.receipts ?? []).some((p) => sameDay(p.date, inc.nextPayDate))
      if (!already) {
        incomeTotal += inc.amount.value
        incomeDetails.push({
          id: crypto.randomUUID(),
          name: inc.name,
          amount: inc.amount.value,
          date: inc.nextPayDate,
          isPaid: false,
          incomeId: inc.id,
        })
      }
    }
  }

  for (const bill of bills) {
    for (const p of bill.payments ?? []) {
      if (sameMonth(p.date, month)) {
        billTotal += p.amount.value
        billDetails.push({
          id: crypto.randomUUID(),
          name: bill.name,
          amount: p.amount.value,
          date: p.date,
          isPaid: true,
          billId: bill.id,
        })
      }
    }
    if (sameMonth(bill.nextDueDate, month) && !billIsPaidFor(bill, bill.nextDueDate)) {
      billTotal += bill.amount.value
      billDetails.push({
        id: crypto.randomUUID(),
        name: bill.name,
        amount: bill.amount.value,
        date: bill.nextDueDate,
        isPaid: false,
        billId: bill.id,
      })
    }
  }

  incomeDetails.sort((a, b) => a.date.getTime() - b.date.getTime())
  billDetails.sort((a, b) => a.date.getTime() - b.date.getTime())

  return {
    income: incomeTotal,
    bills: billTotal,
    net: incomeTotal - billTotal,
    incomeDetails,
    billDetails,
  }
}

