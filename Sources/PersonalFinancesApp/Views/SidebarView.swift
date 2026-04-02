import SwiftUI

struct SidebarView: View {
    @Binding var selected: SidebarSection?
    @EnvironmentObject private var store: AppStore
    private var iconFont: Font { .system(size: 18) }
    enum DueSeverity { case none, soon, overdue }

    var body: some View {
        List(selection: $selected) {
            Section("Bills") {
                NavigationLink(value: SidebarSection.overview) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: icon(for: .overview))
                            .font(iconFont)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(for: .overview))
                            Text(subtitle(for: .overview))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                NavigationLink(value: SidebarSection.income) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "arrow.down.circle")
                            .font(iconFont)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Income")
                            Text(incomeSubtitle())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                let extra: [SidebarSection] = (store.settings.dashboardStyle == .advanced)
                    ? [.dueSoon, .dueThisMonth, .deferred, .paidRecently]
                    : [.deferred]
                ForEach(extra) { s in
                    NavigationLink(value: s) {
                        HStack(alignment: .center, spacing: 10) {
                            if s == .dueSoon {
                                BellIcon(severity: dueSoonSeverity(), font: iconFont)
                            } else {
                                Image(systemName: icon(for: s))
                                    .font(iconFont)
                                    .foregroundStyle(Color.primary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(for: s))
                                Text(subtitle(for: s))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            if store.settings.dashboardStyle == .advanced {
                Section("Core") {
                    ForEach([SidebarSection.accounts, .goals, .debts]) { s in
                        NavigationLink(value: s) {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: icon(for: s))
                                    .font(iconFont)
                                    .foregroundStyle(Color.primary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title(for: s))
                                    Text(subtitle(for: s))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            Section("Reports") {
                NavigationLink(value: SidebarSection.reports) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: icon(for: .reports))
                            .font(iconFont)
                        Text("Reports")
                        Spacer()
                    }
                }
            }
            Section("Settings") {
                NavigationLink(value: SidebarSection.settings) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: icon(for: .settings))
                            .font(iconFont)
                        Text("Settings")
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func title(for s: SidebarSection) -> String {
        switch s {
        case .dueThisMonth: return "Due in \(monthName())"
        case .monthlySummary: return "Summary for \(monthName())"
        default: return s.rawValue
        }
    }

    private func monthName() -> String {
        Calendar.current.monthSymbols[Calendar.current.component(.month, from: Date()) - 1]
    }
    private func currency(from decimal: Decimal) -> String {
        let nf = NumberFormatter(); nf.numberStyle = .currency
        nf.currencyCode = store.settings.displayCurrencyCode
        return nf.string(for: decimal as NSDecimalNumber) ?? "\(decimal)"
    }
    private func icon(for s: SidebarSection) -> String {
        switch s {
        case .overview: return "list.bullet.rectangle"
        case .income: return "arrow.down.circle"
        case .accounts: return "creditcard"
        case .transactions: return "list.bullet"
        case .goals: return "target"
        case .debts: return "percent"
        case .dueSoon: return "bell"
        case .dueThisMonth: return "calendar"
        case .monthlySummary: return "text.justify.left"
        case .paidRecently: return "list.bullet"
        case .reports: return "chart.bar.xaxis"
        case .deferred: return "pause.circle"
        case .settings: return "gearshape"
        }
    }
    private func subtitle(for s: SidebarSection) -> String {
        switch s {
        case .overview:
            let unpaid = store.bills.filter { !$0.hiddenUntilEdited && !$0.isSnoozedActive && !$0.isPaidFor(date: $0.nextDueDate) }.count
            return unpaid == 0 ? "All paid" : (unpaid == 1 ? "1 unpaid" : "\(unpaid) unpaid")
        case .income:
            return incomeSubtitle()
        case .accounts:
            let count = store.accounts.filter { !$0.archived }.count
            return count == 0 ? "No Accounts" : (count == 1 ? "1 account" : "\(count) accounts")
        case .transactions:
            return recentActivitySubtitle()
        case .goals:
            let count = store.goals.filter { !$0.archived }.count
            return count == 0 ? "No Goals" : (count == 1 ? "1 goal" : "\(count) goals")
        case .debts:
            let count = store.debts.filter { !$0.archived }.count
            return count == 0 ? "No Debts" : (count == 1 ? "1 debt" : "\(count) debts")
        case .dueSoon:
            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            let cutoff = cal.date(byAdding: .day, value: 7, to: start) ?? start
            let count = store.bills.filter { !$0.hiddenUntilEdited && !$0.isSnoozedActive && !$0.isPaidFor(date: $0.nextDueDate) && cal.startOfDay(for: $0.nextDueDate) <= cutoff }.count
            return count == 0 ? "All paid" : (count == 1 ? "1 unpaid" : "\(count) unpaid")
        case .dueThisMonth:
            let cal = Calendar.current
            let count = store.bills.filter { !$0.hiddenUntilEdited && !$0.isSnoozedActive && !$0.isPaidFor(date: $0.nextDueDate) && cal.isDate($0.nextDueDate, equalTo: Date(), toGranularity: .month) }.count
            return count == 0 ? "All paid" : (count == 1 ? "1 unpaid" : "\(count) unpaid")
        case .monthlySummary:
            let k = store.kpis()
            return "Net: \(currency(from: k.net))"
        case .deferred:
            let count = store.bills.filter { $0.isSnoozedActive }.count
            return count == 0 ? "No Bills" : (count == 1 ? "1 bill" : "\(count) bills")
        case .paidRecently:
            return recentActivitySubtitle()
        case .reports:
            return ""
        case .settings:
            return ""
        }
    }
    
    private func recentActivitySubtitle() -> String {
        let now = Date()
        let past = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let billCount = store.bills.filter { bill in
            guard let last = bill.payments.max(by: { $0.date < $1.date })?.date else { return false }
            return last >= past
        }.count
        let incomeCount = store.incomes.reduce(0) { acc, inc in
            acc + inc.receipts.filter { $0.date >= past }.count
        }
        let total = billCount + incomeCount
        if total == 0 { return "No Items" }
        if total == 1 { return "1 item" }
        return "\(total) items"
    }
    private func incomeSubtitle() -> String {
        let count = store.incomes.count
        return count == 0 ? "No Incomes" : (count == 1 ? "1 income" : "\(count) incomes")
    }
    private func dueSoonSeverity() -> DueSeverity {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let cutoff = cal.date(byAdding: .day, value: 7, to: start) ?? start
        let hasOverdue = store.bills.contains { !$0.hiddenUntilEdited && cal.startOfDay(for: $0.nextDueDate) < start && !$0.isPaidFor(date: $0.nextDueDate) }
        if hasOverdue { return .overdue }
        let hasSoon = store.bills.contains {
            guard !$0.hiddenUntilEdited else { return false }
            let due = cal.startOfDay(for: $0.nextDueDate)
            return due >= start && due <= cutoff
        }
        if hasSoon { return .soon }
        return .none
    }
}

private struct BellIcon: View {
    let severity: SidebarView.DueSeverity
    let font: Font
    @State private var isWiggling = false
    
    var body: some View {
        Image(systemName: "bell")
            .font(font)
            .foregroundStyle(color)
            .rotationEffect(.degrees(isWiggling ? 10 : 0), anchor: .top)
            .animation(isWiggling ? .easeInOut(duration: 0.1).repeatCount(6, autoreverses: true) : .default, value: isWiggling)
            .task {
                // Subtle nudge every few minutes while there is something due
                while true {
                    try? await Task.sleep(nanoseconds: 180 * 1_000_000_000)
                    if severity != .none {
                        isWiggling = true
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        isWiggling = false
                    }
                }
            }
    }
    
    private var color: Color {
        switch severity {
        case .overdue: return .red
        case .soon: return .yellow
        case .none: return .secondary
        }
    }
}
