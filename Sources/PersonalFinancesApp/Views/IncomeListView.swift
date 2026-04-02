import SwiftUI

struct IncomeListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var sourceFilter: Income.Source? = nil
    
    private var filtered: [Income] {
        var items = store.incomes
        if let day = store.selectedIncomeDay {
            items = items.filter { Calendar.current.isDate($0.nextPayDate, inSameDayAs: day) }
        }
        if let f = sourceFilter {
            items = items.filter { $0.source == f }
        }
        if !search.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        return items.sorted { $0.nextPayDate < $1.nextPayDate }
    }
    
    var body: some View {
        Group {
            if store.settings.dashboardStyle == .basic {
                basicIncome()
            } else {
                advancedIncome()
            }
        }
    }
    
    // MARK: - Advanced (original)
    private func advancedIncome() -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Income")
                    .font(.title2.bold())
                Spacer()
                if let day = store.selectedIncomeDay {
                    Text(longDate(day))
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
                    Button {
                        withAnimation { store.selectedIncomeDay = nil }
                    } label: {
                        Label("Clear Day", systemImage: "xmark.circle")
                    }
                }
                Menu {
                    Button("All Sources") { sourceFilter = nil }
                    Divider()
                    ForEach(Income.Source.allCases, id: \.self) { s in
                        Button(s.rawValue.capitalized) { sourceFilter = s }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(sourceFilter?.rawValue.capitalized ?? "All Sources")
                        Image(systemName: "chevron.down").font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.15)))
                }
            }
            .padding([.horizontal, .top])
            
            List(selection: $store.selectedIncomeID) {
                ForEach(filtered) { inc in
                    Button {
                        store.selectedIncomeID = inc.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: symbol(for: inc.source))
                                .font(.title3)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(inc.name).font(.headline)
                                Text(inc.recurrence.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(format(amount: inc.amount))
                                    .monospacedDigit()
                                HStack(spacing: 6) {
                                    Text(format(date: inc.nextPayDate))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    let received = inc.receipts.contains { Calendar.current.isDate($0.date, inSameDayAs: inc.nextPayDate) }
                                    let d = daysUntil(inc.nextPayDate)
                                    if !received && d <= 0 {
                                        Text(dueBadgeText(for: inc))
                                            .font(.caption.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(badgeColor(for: inc))
                                            .foregroundStyle(.white)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tag(inc.id)
                }
            }
            .searchable(text: $search)
        }
        .padding(.bottom)
    }
    
    // MARK: - Basic (simplified)
    private func basicIncome() -> some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            // NEXT INCOME block (like basic dashboard)
            if let inc = nextIncomeObject() {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NEXT INCOME").font(.caption).foregroundStyle(.secondary)
                    Text(inc.name).font(.largeTitle.bold())
                    Text(format(amount: inc.amount)).font(.largeTitle.monospacedDigit())
                    let d = daysUntil(inc.nextPayDate)
                    let line = d == 0 ? "Expected today" : (d < 0 ? "Missed \(-d) days" : "Due in \(d) days")
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(d < 0 ? Color.purple : (d == 0 ? Color.orange : .secondary))
                }
                .padding(.top, 6)
                .padding(.horizontal)
            }
            // Numbers row
            let k = incomeKpis()
            HStack {
                HStack(spacing: 6) { Text("Received:"); Spacer(); Text(format(value: k.received)).monospacedDigit() }
                HStack(spacing: 6) { Text("Upcoming:"); Spacer(); Text(format(value: k.upcoming)).monospacedDigit() }
                HStack(spacing: 6) { Text("Total:"); Spacer(); Text(format(value: k.total)).monospacedDigit() }
            }
            .font(.title3)
            .padding(.horizontal)
            // Status line
            Text(k.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            // Day‑filtered list wins (like dashboard)
            if let day = store.selectedIncomeDay {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Due on " + longDate(day)).font(.headline)
                    minimalIncomeList(items: incomesOn(day: day))
                }
                .padding(.horizontal)
            } else {
                // Sections: Missed / Due Soon / Upcoming
                VStack(alignment: .leading, spacing: 26) {
                    let missed = incomesMissed()
                    if !missed.isEmpty {
                        Text("Missed").font(.headline)
                        Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 0.5)
                        minimalIncomeList(items: missed)
                    }
                    let soon = incomesDueSoon()
                    if !soon.isEmpty {
                        Text("Due Soon").font(.headline).padding(.top, missed.isEmpty ? 0 : 4)
                        Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 0.5)
                        minimalIncomeList(items: soon)
                    }
                    let up = incomesUpcoming()
                    if !up.isEmpty {
                        Text("Upcoming").font(.headline)
                        Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 0.5)
                        minimalIncomeList(items: up)
                    }
                }
                .padding(.horizontal)
            }
            // Inline minimal search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search income", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
        }
    }
    
    // MARK: - Helpers for Basic
    private func minimalIncomeList(items: [Income]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { inc in
                let isSelected = (store.selectedIncomeID == inc.id)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(inc.name).font(.body)
                        Spacer()
                        Text(format(amount: inc.amount)).monospacedDigit()
                    }
                    let d = daysUntil(inc.nextPayDate)
                    Text(format(date: inc.nextPayDate) + (d < 0 ? " • missed \(-d)d" : (d == 0 ? " • expected today" : " • in \(d) days")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                .onTapGesture { store.selectedIncomeID = inc.id }
                if isSelected {
                    HStack(spacing: 8) {
                        Button("Log Receipt") { store.logReceipt(for: inc.id) }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        Button("Handle Later") { store.skipIncome(for: inc.id) }
                            .buttonStyle(.bordered)
                    }
                    .controlSize(.small)
                }
            }
        }
    }
    private func incomeKpis() -> (received: Decimal, upcoming: Decimal, total: Decimal, status: String) {
        let cal = Calendar.current
        let now = Date()
        let received: Decimal = store.incomes.flatMap { $0.receipts }.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }.reduce(Decimal(0)) { $0 + $1.amount.value }
        let upcoming: Decimal = store.incomes.reduce(Decimal(0)) { acc, inc in
            let dueThisMonth = cal.isDate(inc.nextPayDate, equalTo: now, toGranularity: .month)
            let notLogged = !inc.receipts.contains(where: { cal.isDate($0.date, inSameDayAs: inc.nextPayDate) })
            return acc + ((dueThisMonth && notLogged) ? inc.amount.value : 0)
        }
        let total = received + upcoming
        let missedCount = store.incomes.filter { inc in
            let d = daysUntil(inc.nextPayDate)
            let notLogged = !inc.receipts.contains(where: { p in Calendar.current.isDate(p.date, inSameDayAs: inc.nextPayDate) })
            return d < 0 && notLogged
        }.count
        let status = missedCount > 0 ? "Missed receipts need attention" : "You’re fine this month"
        return (received, upcoming, total, status)
    }
    private func incomesOn(day: Date) -> [Income] {
        store.incomes.filter { Calendar.current.isDate($0.nextPayDate, inSameDayAs: day) }
            .sorted { $0.nextPayDate < $1.nextPayDate }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    private func nextIncomeObject() -> Income? {
        let eligible = store.incomes.filter { inc in
            let notLogged = !inc.receipts.contains(where: { p in Calendar.current.isDate(p.date, inSameDayAs: inc.nextPayDate) })
            return notLogged
        }
        return eligible.min(by: { $0.nextPayDate < $1.nextPayDate })
    }
    private func incomesMissed() -> [Income] {
        store.incomes.filter { inc in
            daysUntil(inc.nextPayDate) < 0 && !inc.receipts.contains(where: { p in Calendar.current.isDate(p.date, inSameDayAs: inc.nextPayDate) })
        }
        .sorted { $0.nextPayDate < $1.nextPayDate }
        .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    private func incomesDueSoon() -> [Income] {
        store.incomes.filter { inc in
            let d = daysUntil(inc.nextPayDate)
            return d >= 0 && d <= 5 && !inc.receipts.contains(where: { p in Calendar.current.isDate(p.date, inSameDayAs: inc.nextPayDate) })
        }
        .sorted { $0.nextPayDate < $1.nextPayDate }
        .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    private func incomesUpcoming() -> [Income] {
        store.incomes.filter {
            let d = daysUntil($0.nextPayDate)
            return d >= 6 && d <= 31
        }
        .sorted { $0.nextPayDate < $1.nextPayDate }
        .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    private func format(value: Decimal) -> String { format(amount: DecimalAmount(currencyCode: store.settings.displayCurrencyCode, value: value)) }
    
    private func format(amount: DecimalAmount) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = store.settings.displayCurrencyCode
        return nf.string(for: amount.value as NSDecimalNumber) ?? "\(amount.value)"
    }
    private func format(date: Date) -> String {
        let df = DateFormatter(); df.dateStyle = .medium; return df.string(from: date)
    }
    private func longDate(_ d: Date) -> String {
        let df = DateFormatter(); df.dateStyle = .full; return df.string(from: d)
    }
    private func symbol(for s: Income.Source) -> String {
        switch s {
        case .salary: return "dollarsign.arrow.circlepath"
        case .freelance: return "laptopcomputer"
        case .rental: return "house"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .other: return "circle.grid.2x2"
        }
    }
    
    private func daysUntil(_ date: Date) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: start, to: end).day ?? 0
    }
    private func dueBadgeText(for income: Income) -> String {
        let d = daysUntil(income.nextPayDate)
        if d == 0 { return "Expected today" }
        return "Missed \(-d)d"
    }
    private func badgeColor(for income: Income) -> Color {
        let d = daysUntil(income.nextPayDate)
        return d == 0 ? .orange : .purple
    }
}
