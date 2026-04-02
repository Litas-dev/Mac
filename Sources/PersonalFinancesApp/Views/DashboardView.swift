import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @State private var search: String = ""
    @State private var showForecast: Bool = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let day = store.selectedDay {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Due on " + longDate(day)).font(.headline)
                            priorityList(items: dueOn(day: day))
                        }
                    }
                } else if store.settings.dashboardStyle == .basic {
                    minimalDashboard()
                } else {
                    riskBanner()
                    kpiStrip()
                    accountsStrip()
                    budgetsStrip()
                    forecastStrip()
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Overdue Total: " + currency(overdueTotal()))
                                .font(.headline)
                        }
                    }
                    let crit = overdueCritical()
                    if !crit.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Critical (10+ days overdue)").font(.headline).foregroundStyle(.red)
                                priorityList(items: crit, emphasizeTop: true, style: .critical)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.06)))
                        .overlay(
                            Rectangle()
                                .fill(Color.red.opacity(0.4))
                                .frame(width: 3)
                                .cornerRadius(2),
                            alignment: .leading
                        )
                    }
                    let recent = overdueRecent()
                    if !recent.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Recent overdue (1–9 days)").font(.headline)
                                priorityList(items: recent, style: .recent)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(scheme == .dark ? 0.08 : 0.06)))
                    }
                    let soon = dueSoon()
                    if !soon.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Due Soon (0–5 days)").font(.headline)
                                priorityList(items: soon, style: .dueSoon)
                            }
                        }
                    }
                    let up = upcoming()
                    if !up.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Upcoming").font(.headline)
                                priorityList(items: up)
                            }
                        }
                    }
                }
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .top) { headerBar() }
        .searchable(text: $search, prompt: "Search")
    }
    
    private func budgetsStrip() -> some View {
        let cal = Calendar.current
        let now = Date()
        // compute spent per budget key (payments in current month)
        var spent: [String: Decimal] = [:]
        for b in store.bills {
            let key = store.settings.budgetKey(for: b)
            let s = b.payments
                .filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
                .reduce(Decimal(0)) { $0 + $1.amount.value }
            if s > 0 {
                spent[key, default: 0] += s
            }
        }
        let rows = store.settings.monthlyBudgets
            .filter { $0.value > 0 }
            .map { (key: $0.key, used: spent[$0.key] ?? 0, total: $0.value) }
            .sorted(by: { AppSettings.budgetDisplayName(for: $0.key).localizedCaseInsensitiveCompare(AppSettings.budgetDisplayName(for: $1.key)) == .orderedAscending })
        return Group {
            if !rows.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Budgets").font(.headline)
                        ForEach(rows, id: \.key) { item in
                            let used = item.used
                            let total = item.total
                            let ratio = (used / total).doubleValueRounded(4)
                            let pct = min(ratio, 1.0)
                            HStack {
                                Text(AppSettings.budgetDisplayName(for: item.key)).frame(width: 140, alignment: .leading)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15))
                                        RoundedRectangle(cornerRadius: 6).fill(ratio > 1.0 ? Color.red : (ratio >= 0.8 ? Color.yellow : Color.green))
                                            .frame(width: CGFloat(pct) * geo.size.width)
                                    }
                                }
                                .frame(height: 10)
                                Text("\(store.settings.displayCurrencyCode) \(NSDecimalNumber(decimal: used).stringValue) / \(NSDecimalNumber(decimal: total).stringValue)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if rows.contains(where: { let r = ($0.used / $0.total).doubleValueRounded(4); return r >= 0.8 && r <= 1.0 }) {
                            Text("Warning: one or more budgets above 80%").font(.footnote).foregroundStyle(.yellow)
                        }
                        if rows.contains(where: { ($0.used / $0.total).doubleValueRounded(4) > 1.0 }) {
                            Text("Exceeded: some budgets are over 100%").font(.footnote).foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }
    
    private func accountsStrip() -> some View {
        let active = store.accounts.filter { !$0.archived }
        return Group {
            if !active.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Accounts").font(.headline)
                            Spacer()
                            if store.settings.preferManualForecastBalance {
                                Text("Balances hidden")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Net Worth: " + currency(store.netWorth(in: store.settings.displayCurrencyCode)))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(active.sorted(by: { $0.name < $1.name }).prefix(5)) { a in
                            HStack {
                                Text(a.name)
                                Spacer()
                                if store.settings.preferManualForecastBalance {
                                    Text("—")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(currency(store.balance(forAccountId: a.id)))
                                        .monospacedDigit()
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    private func forecastStrip() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Cash Flow Forecast").font(.headline)
                    Spacer()
                    Button {
                        withAnimation { showForecast.toggle() }
                    } label: {
                        Image(systemName: showForecast ? "chevron.down" : "chevron.right")
                    }
                    .buttonStyle(.plain)
                }
                if showForecast {
                    HStack(spacing: 12) {
                        forecastBox(days: 7)
                        forecastBox(days: 14)
                        forecastBox(days: 30)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
    private func forecastBox(days: Int) -> some View {
        let f = forecast(horizonDays: days)
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(days)d").font(.caption).foregroundStyle(.secondary)
            Text("End: " + currency(f.end)).font(.body.monospacedDigit())
            Text("Min: " + currency(f.min) + " " + shortDate(f.minDate))
                .font(.footnote).foregroundStyle(f.min < 0 ? .red : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(scheme == .dark ? 0.12 : 0.08)))
    }
    private func forecast(horizonDays: Int) -> (end: Decimal, min: Decimal, minDate: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let endDate = cal.date(byAdding: .day, value: horizonDays, to: today) ?? today
        var events: [(Date, Decimal)] = []
        // Bills (negative)
        for bill in store.bills {
            var d = bill.nextDueDate
            while d <= endDate {
                if d >= today && !bill.isPaidFor(date: d) {
                    events.append((cal.startOfDay(for: d), -bill.amount.value))
                }
                if bill.recurrence == .once { break }
                d = bill.recurrence.advance(from: d)
            }
        }
        // Incomes (positive)
        for inc in store.incomes {
            var d = inc.nextPayDate
            while d <= endDate {
                let logged = inc.receipts.contains { Calendar.current.isDate($0.date, inSameDayAs: d) }
                if d >= today && !logged {
                    events.append((cal.startOfDay(for: d), inc.amount.value))
                }
                if inc.recurrence == .once { break }
                d = inc.recurrence.advance(from: d)
            }
        }
        events.sort { $0.0 < $1.0 }
        var bal = store.computedAvailableBalance
        var minBal = bal
        var minDate = today
        for (date, delta) in events {
            bal += delta
            if bal < minBal {
                minBal = bal
                minDate = date
            }
        }
        return (bal, minBal, minDate)
    }
    
    private func minimalDashboard() -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if let b = nextBillObject() {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NEXT BILL").font(.caption).foregroundStyle(.secondary)
                    Text(b.name).font(.largeTitle.bold())
                    Text(currency(b.amount)).font(.largeTitle.monospacedDigit())
                    let d = daysUntil(b.nextDueDate)
                    let line = d == 0 ? "Due today" : (d < 0 ? "Overdue \(-d) days" : "Due in \(d) days")
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(d < 0 ? Color.red : (d <= 5 ? Color.yellow : .secondary))
                }
                .padding(.top, 6)
            }
            let k = kpis()
            HStack {
                HStack(spacing: 6) { Text("Income:"); Spacer(); Text(currency(k.income)).monospacedDigit() }
                HStack(spacing: 6) { Text("Bills:"); Spacer(); Text(currency(k.bills)).monospacedDigit() }
                HStack(spacing: 6) { Text("Left:"); Spacer(); Text(currency(k.net)).monospacedDigit().foregroundColor(k.net >= 0 ? .primary : .red) }
            }
            .font(.title3)
            Text(minimalStatusLine())
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !store.accounts.filter({ !$0.archived }).isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACCOUNTS").font(.caption).foregroundStyle(.secondary)
                        Text("Net Worth: " + currency(store.netWorth(in: store.settings.displayCurrencyCode)))
                            .font(.title3.monospacedDigit())
                    }
                }
            }
            VStack(alignment: .leading, spacing: 26) {
                let od = overdue()
                if !od.isEmpty {
                    Text("Overdue").font(.headline)
                    Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 0.5)
                    minimalList(items: od, colorize: true)
                }
                let soon = dueSoon()
                if !soon.isEmpty {
                    Text("Due Soon").font(.headline).padding(.top, od.isEmpty ? 0 : 4)
                    Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 0.5)
                    minimalList(items: soon, colorize: true)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private func minimalList(items: [RowItem], colorize: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items.prefix(8)) { item in
                let isSelected = (store.selectedBillID == item.bill.id)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.bill.name).font(.body)
                        Spacer()
                        Text(currency(item.bill.amount))
                            .font(Typography.amountFont(for: store.settings))
                            .foregroundStyle(item.days < 0 ? Color.red : (item.days <= 5 ? Color.yellow : Color.primary))
                    }
                    Text(shortDate(item.bill.nextDueDate) + " • " + (item.days < 0 ? "\(-item.days) days late" : (item.days == 0 ? "due today" : "in \(item.days) days")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                .onTapGesture { store.selectedBillID = item.bill.id }
                if isSelected {
                    HStack(spacing: 8) {
                        Button("Mark Paid") { store.logPayment(for: item.bill.id) }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        Menu {
                            Button("+1 day") { store.snooze(for: item.bill.id, preset: .day1) }
                            Button("+3 days") { store.snooze(for: item.bill.id, preset: .day3) }
                            Button("+7 days") { store.snooze(for: item.bill.id, preset: .day7) }
                            Button("Next week") { store.snooze(for: item.bill.id, preset: .nextWeek) }
                            Button("End of month") { store.snooze(for: item.bill.id, preset: .endOfMonth) }
                        } label: { Text("Snooze") }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
    
    private func nextBillObject() -> Bill? {
        let eligible = store.bills.filter { !$0.hiddenUntilEdited && !$0.isSnoozedActive && !$0.isPaidFor(date: $0.nextDueDate) }
        return eligible.min(by: { $0.nextDueDate < $1.nextDueDate })
    }
    
    private func minimalStatusLine() -> String {
        let overdueCount = store.bills.filter { daysUntil($0.nextDueDate) < 0 && !$0.hiddenUntilEdited && !$0.isSnoozedActive && !$0.isPaidFor(date: $0.nextDueDate) }.count
        if overdueCount > 0 { return "Overdue bills need attention" }
        if let upcoming = upcomingBillAlert() { return upcoming.text }
        let k = kpis()
        if k.net < 0 { return "Warning: negative after bills this month" }
        return "You’re fine this month"
    }
    
    private func headerBar() -> some View {
        Group {
            if let day = store.selectedDay {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                        Text(longDate(day))
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.15)))
                    Button {
                        withAnimation { store.selectedDay = nil }
                    } label: {
                        Label("Back to Dashboard", systemImage: "arrow.uturn.left")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(.accentColor)
                    .help("Clear date filter and show full dashboard")
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .overlay(Divider(), alignment: .bottom)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 6)
                    .overlay(Divider().opacity(0.12), alignment: .bottom)
            }
        }
    }
    
    private func riskBanner() -> some View {
        let overdueCount = store.bills.filter { daysUntil($0.nextDueDate) < 0 && !$0.hiddenUntilEdited && !$0.isSnoozedActive && !$0.isPaidFor(date: $0.nextDueDate) }.count
        let k = kpis()
        let upcoming = upcomingBillAlert()
        let reliability = reliabilityAlert()
        let text: String
        let color: Color
        
        if overdueCount > 0 {
            let critical = overdueCritical().count
            let recent = overdueRecent().count
            text = "\(critical) critical, \(recent) overdue bills"
            color = .red
        } else if let upcoming {
            text = upcoming.text
            color = upcoming.color
        } else if let reliability {
            text = reliability.text
            color = reliability.color
        } else if k.net < 0 {
            text = "Warning: negative after bills this month"
            color = .yellow
        } else {
            text = "You are on track this month"
            color = .green
        }
        let hasWarning = overdueCount > 0 || upcoming != nil || reliability != nil || k.net < 0
        return HStack {
            Image(systemName: hasWarning ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
            Text(text).font(.headline)
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(color))
    }

    private func upcomingBillAlert() -> (text: String, color: Color)? {
        let balance = store.computedAvailableBalance
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let in3Days = cal.date(byAdding: .day, value: 3, to: today) ?? today
        let in7Days = cal.date(byAdding: .day, value: 7, to: today) ?? today
        
        let upcomingBills7 = store.bills.filter {
            !$0.hiddenUntilEdited &&
            !$0.isSnoozedActive &&
            !$0.isPaidFor(date: $0.nextDueDate) &&
            cal.startOfDay(for: $0.nextDueDate) >= today &&
            cal.startOfDay(for: $0.nextDueDate) <= in7Days
        }
        
        guard let urgent = upcomingBills7.min(by: { $0.nextDueDate < $1.nextDueDate }) else { return nil }
        let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: urgent.nextDueDate)).day ?? 0
        let dayText = days == 0 ? "today" : (days == 1 ? "tomorrow" : "in \(days) days")
        let within3 = cal.startOfDay(for: urgent.nextDueDate) <= in3Days
        let color: Color = within3 ? .red : .yellow
        
        if urgent.amount.value > balance {
            return (text: "You have \(urgent.name) (\(currency(urgent.amount))) due \(dayText) and only \(currency(balance)) available", color: .red)
        }
        if upcomingBills7.count > 1 {
            return (text: "\(upcomingBills7.count) bills due within 7 days • next: \(urgent.name) \(dayText)", color: color)
        }
        return (text: "\(urgent.name) (\(currency(urgent.amount))) due \(dayText)", color: color)
     }
     
     private func reliabilityAlert() -> (text: String, color: Color)? {
         let cal = Calendar.current
         let now = Date()
         let todayDay = cal.component(.day, from: now)
         
         for bill in store.bills {
             if bill.hiddenUntilEdited || bill.isPaidFor(date: bill.nextDueDate) { continue }
             
             // Need at least 2 payments to establish a habit
             if bill.payments.count < 2 { continue }
             
             let days = bill.payments.map { cal.component(.day, from: $0.date) }
             let usualDay = days.reduce(0, +) / days.count
             
             // If today is past the usual day but before the actual due date
             if todayDay > (usualDay + 1) && now < bill.nextDueDate {
                 let suffix = {
                    let d = usualDay
                    if d % 10 == 1 && d != 11 { return "st" }
                    if d % 10 == 2 && d != 12 { return "nd" }
                    if d % 10 == 3 && d != 13 { return "rd" }
                    return "th"
                 }()
                 return (text: "You usually pay \(bill.name) by the \(usualDay)\(suffix). It's now the \(todayDay)th.", color: .orange)
             }
         }
         return nil
     }

     private func kpiStrip() -> some View {
        let k = kpis()
        return HStack(spacing: 12) {
            kpiBox(title: "Income This Month", value: currency(k.income))
            kpiBox(title: "Bills This Month", value: currency(k.bills))
            kpiBox(title: "Left After Bills", value: currency(k.net), accent: k.net >= 0 ? .green : .red)
            kpiBox(title: "Next Bill", value: k.nextBillText, accent: k.nextAccent)
        }
    }
    
    private func kpiBox(title: String, value: String, accent: Color = .accentColor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit()).foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(scheme == .dark ? 0.12 : 0.08)))
    }
    
    private struct RowItem: Identifiable {
        let bill: Bill
        let days: Int
        var id: UUID { bill.id }
    }
    private enum ListStyle { case critical, recent, dueSoon, normal }
    private func priorityList(items: [RowItem], emphasizeTop: Bool = false, style: ListStyle = .normal) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(items.prefix(8).enumerated()), id: \.element.bill.id) { index, item in
                let isSelected = (store.selectedBillID == item.bill.id)
                HStack(spacing: 10) {
                    Image(systemName: item.bill.category.symbolName)
                        .font(.title3)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.bill.name)
                            .font(emphasizeTop && index == 0 ? .headline.weight(.bold) : .headline)
                        Text(shortDate(item.bill.nextDueDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(currency(item.bill.amount))
                            .font(Typography.amountFont(for: store.settings))
                            .foregroundStyle((style == .critical && item.days < 0) ? Color.red : Color.primary)
                        HStack(spacing: 6) {
                            if item.days == 0 {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                            Text(dayBadgeText(item.days))
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(dayBadgeColor(item.days))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        if isSelected {
                            HStack {
                                Button("Mark Paid") { store.logPayment(for: item.bill.id) }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                Menu {
                                    Button("+1 day") { store.snooze(for: item.bill.id, preset: .day1) }
                                    Button("+3 days") { store.snooze(for: item.bill.id, preset: .day3) }
                                    Button("+7 days") { store.snooze(for: item.bill.id, preset: .day7) }
                                    Button("Next week") { store.snooze(for: item.bill.id, preset: .nextWeek) }
                                    Button("End of month") { store.snooze(for: item.bill.id, preset: .endOfMonth) }
                                } label: {
                                    Label("Snooze", systemImage: "pause.circle")
                                }
                                .buttonStyle(.bordered)
                            }
                            // use environment control size
                        }
                    }
                }
                .padding(emphasizeTop && index == 0 ? 10 : 6)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor.opacity(0.35) :
                              (emphasizeTop && index == 0 && style == .critical ? Color.red.opacity(0.07) : Color.clear))
                )
                .overlay(
                    emphasizeTop && index == 0 && style == .critical ?
                    RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.5), lineWidth: 1) : nil
                )
                .onTapGesture { store.selectedBillID = item.bill.id }
                Divider()
            }
        }
    }
    
    private func overdue() -> [RowItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return store.bills
            .filter { !$0.hiddenUntilEdited && !$0.isSnoozedActive && cal.startOfDay(for: $0.nextDueDate) < today && !$0.isPaidFor(date: $0.nextDueDate) }
            .filter { matchesSearch($0) }
            .map { RowItem(bill: $0, days: daysUntil($0.nextDueDate)) }
            .sorted { $0.days < $1.days }
    }
    private func overdueCritical() -> [RowItem] {
        overdue().filter { $0.days <= -10 }
    }
    private func overdueRecent() -> [RowItem] {
        overdue().filter { $0.days < 0 && $0.days >= -9 }
    }
    private func dueSoon() -> [RowItem] {
        let items = within(days: 0...5)
        return items.sorted { $0.days < $1.days }
    }
    private func upcoming() -> [RowItem] {
        let items = within(days: 6...31)
        return items.sorted { $0.days < $1.days }
    }
    private func dueOn(day: Date) -> [RowItem] {
        let cal = Calendar.current
        return store.bills
            .filter {
                cal.isDate($0.nextDueDate, inSameDayAs: day)
                && !$0.hiddenUntilEdited
                && !$0.isSnoozedActive
                && !$0.isPaidFor(date: $0.nextDueDate)
            }
            .filter { matchesSearch($0) }
            .map { RowItem(bill: $0, days: daysUntil($0.nextDueDate)) }
            .sorted { $0.days < $1.days }
    }
    private func within(days range: ClosedRange<Int>) -> [RowItem] {
        store.bills
            .filter {
                let d = daysUntil($0.nextDueDate)
                return d >= range.lowerBound && d <= range.upperBound && !$0.hiddenUntilEdited && !$0.isSnoozedActive
            }
            .filter { matchesSearch($0) }
            .map { RowItem(bill: $0, days: daysUntil($0.nextDueDate)) }
    }
    private func matchesSearch(_ bill: Bill) -> Bool {
        if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return bill.name.localizedCaseInsensitiveContains(search)
    }
    
    private func kpis() -> (income: Decimal, bills: Decimal, net: Decimal, nextBillText: String, nextAccent: Color) {
        let cal = Calendar.current
        let now = Date()
        let income: Decimal = store.incomes.reduce(0) { acc, inc in
            let received = inc.receipts
                .filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
                .reduce(Decimal(0)) { $0 + $1.amount.value }
            let upcoming = cal.isDate(inc.nextPayDate, equalTo: now, toGranularity: .month) &&
            !inc.receipts.contains { Calendar.current.isDate($0.date, inSameDayAs: inc.nextPayDate) }
                ? inc.amount.value : 0
            return acc + received + upcoming
        }
        let paidThisMonth = store.bills.flatMap { $0.payments }.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }.reduce(Decimal(0)) { $0 + $1.amount.value }
        let unpaidThisMonth = store.bills.filter {
            cal.isDate($0.nextDueDate, equalTo: now, toGranularity: .month) && !$0.isPaidFor(date: $0.nextDueDate)
        }.reduce(Decimal(0)) { $0 + $1.amount.value }
        let bills: Decimal = paidThisMonth + unpaidThisMonth
        let net = income - bills
        let eligible = store.bills.filter { !$0.hiddenUntilEdited && !$0.isSnoozedActive && !$0.isPaidFor(date: $0.nextDueDate) }
        let next = eligible.min(by: { $0.nextDueDate < $1.nextDueDate })
        let nextText: String = {
            guard let b = next else { return "None" }
            let d = daysUntil(b.nextDueDate)
            if d == 0 { return "\(b.name) today" }
            if d < 0 { return "\(b.name) overdue \(-d)d" }
            return "\(b.name) in \(d) days"
        }()
        let nextAccent: Color = {
            guard let b = next else { return .secondary }
            let d = daysUntil(b.nextDueDate)
            if d <= 0 { return .red }
            if d <= 5 { return .yellow }
            return .accentColor
        }()
        return (income, bills, net, nextText, nextAccent)
    }
    
    private func overdueTotal() -> DecimalAmount {
        let total = store.bills.filter { daysUntil($0.nextDueDate) < 0 && !$0.hiddenUntilEdited && !$0.isPaidFor(date: $0.nextDueDate) }
            .reduce(Decimal(0)) { $0 + $1.amount.value }
        return DecimalAmount(currencyCode: store.settings.displayCurrencyCode, value: total)
    }
    
    private func currency(_ amount: DecimalAmount) -> String {
        currency(amount.value)
    }
    private func currency(_ value: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = store.settings.displayCurrencyCode
        return nf.string(for: value as NSDecimalNumber) ?? "\(value)"
    }
    private func shortDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: d)
    }
    private func longDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .full
        return df.string(from: d)
    }
    private func daysUntil(_ date: Date) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: start, to: end).day ?? 0
    }
    private func dayBadgeText(_ d: Int) -> String {
        if d == 0 { return "Due today" }
        if d < 0 { return "Overdue \(-d)d" }
        return "Due in \(d)d"
    }
    private func dayBadgeColor(_ d: Int) -> Color {
        if d <= 0 { return .red }
        if d <= 5 { return .yellow }
        return .blue
    }
}

private extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
