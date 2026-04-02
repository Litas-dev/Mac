import SwiftUI

struct BillsListView: View {
    @EnvironmentObject private var store: AppStore
    let section: SidebarSection
    var onEdit: ((Bill) -> Void)? = nil
    @State private var search = ""
    @State private var showingAdd = false
    @State private var filter: Filter = .allItems
    @State private var categoryFilter: Bill.Category? = nil
    @State private var paidSortNewestFirst: Bool = true
    @State private var overviewSortSoonestFirst: Bool = true
    @State private var dueMonthSortSoonestFirst: Bool = true

    enum Filter: String, CaseIterable, Identifiable {
        case allItems = "All Items"
        case dueSoon = "Due Soon"
        case thisMonth = "This Month"
        case overdue = "Overdue"
        var id: String { rawValue }
    }

    private var filtered: [Bill] {
        var items = store.bills
        if let day = store.selectedDay {
            items = items.filter { Calendar.current.isDate($0.nextDueDate, inSameDayAs: day) }
        }
        switch section {
        case .overview:
            break
        case .income:
            break
        case .accounts:
            break
        case .transactions:
            break
        case .goals:
            break
        case .debts:
            break
        case .deferred:
            items = items.filter { $0.isSnoozedActive }
        case .settings:
            break
        case .dueSoon:
            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            let cutoff = cal.date(byAdding: .day, value: 7, to: start) ?? start
            items = items.filter {
                let due = cal.startOfDay(for: $0.nextDueDate)
                return due <= cutoff
            }
        case .dueThisMonth:
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            // Show items due this month OR overdue (even if from previous months)
            items = items.filter {
                cal.isDate($0.nextDueDate, equalTo: Date(), toGranularity: .month) || cal.startOfDay(for: $0.nextDueDate) < today
            }
        case .paidRecently:
            let now = Date()
            let past = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
            items = items.filter { bill in
                guard let last = bill.payments.max(by: { $0.date < $1.date })?.date else { return false }
                return last >= past
            }
        case .reports:
            break
        case .monthlySummary:
            break
        }
        switch filter {
        case .allItems: break
        case .dueSoon:
            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            let cutoff = cal.date(byAdding: .day, value: 7, to: start) ?? start
            items = items.filter {
                let due = cal.startOfDay(for: $0.nextDueDate)
                return due <= cutoff
            }
        case .thisMonth:
            let cal = Calendar.current
            items = items.filter { cal.isDate($0.nextDueDate, equalTo: Date(), toGranularity: .month) }
        case .overdue:
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            items = items.filter { cal.startOfDay(for: $0.nextDueDate) < today }
        }
        if section != .paidRecently && section != .deferred {
            items = items.filter { !$0.hiddenUntilEdited && !$0.isSnoozedActive }
        }
        if !search.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        if let cat = categoryFilter {
            items = items.filter { $0.category == cat }
        }
        if section == .paidRecently {
            return items.sorted {
                let d1 = $0.payments.max(by: { $0.date < $1.date })?.date ?? .distantPast
                let d2 = $1.payments.max(by: { $0.date < $1.date })?.date ?? .distantPast
                return paidSortNewestFirst ? d1 > d2 : d1 < d2
            }
        } else {
            if section == .overview {
                return items.sorted { overviewSortSoonestFirst ? $0.nextDueDate < $1.nextDueDate : $0.nextDueDate > $1.nextDueDate }
            } else if section == .dueThisMonth {
                return items.sorted { dueMonthSortSoonestFirst ? $0.nextDueDate < $1.nextDueDate : $0.nextDueDate > $1.nextDueDate }
            } else if section == .deferred {
                return items.sorted { ($0.snoozeUntil ?? .distantFuture) < ($1.snoozeUntil ?? .distantFuture) }
            } else {
                return items.sorted { $0.nextDueDate < $1.nextDueDate }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.rawValue)
                        .font(.title2.bold())
                    if section == .deferred {
                        Text("Deferred bills")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Temporarily hidden. They will return automatically.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let day = store.selectedDay {
                    Text(longDate(day))
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
                    Button {
                        withAnimation { store.selectedDay = nil }
                    } label: {
                        Label("Clear Day", systemImage: "xmark.circle")
                    }
                }
                HStack(spacing: 10) {
                    Menu {
                        Button("All Items") { categoryFilter = nil }
                        Divider()
                        ForEach(Bill.Category.allCases, id: \.self) { c in
                            Button(c.rawValue.capitalized) { categoryFilter = c }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(categoryFilter?.rawValue.capitalized ?? "All Items")
                            Image(systemName: "chevron.down")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.15)))
                    }
                    if section == .paidRecently {
                        Picker("", selection: $paidSortNewestFirst) {
                            Text("Newest").tag(true)
                            Text("Oldest").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    } else if section == .overview {
                        Picker("", selection: $overviewSortSoonestFirst) {
                            Text("Soonest").tag(true)
                            Text("Latest").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    } else if section == .dueThisMonth {
                        Picker("", selection: $dueMonthSortSoonestFirst) {
                            Text("Soonest").tag(true)
                            Text("Latest").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                }
            }
            .padding([.horizontal, .top])

            List(selection: $store.selectedBillID) {
                ForEach(filtered) { bill in
                    Button {
                        store.selectedBillID = bill.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: bill.category.symbolName)
                                .font(.title3)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(bill.name).font(.headline)
                                Text(bill.recurrence.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(format(amount: bill.amount))
                                    .font(Typography.amountFont(for: store.settings))
                                if section == .paidRecently {
                                    if let last = bill.payments.max(by: { $0.date < $1.date })?.date {
                                        Text("Paid " + format(date: last))
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    }
                                } else if section == .deferred {
                                    HStack(spacing: 6) {
                                        Text(format(date: bill.snoozeUntil ?? bill.nextDueDate))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(snoozeBadgeText(for: bill))
                                            .font(.caption.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.gray)
                                            .foregroundStyle(.white)
                                            .clipShape(Capsule())
                                        Button("Resume") { store.clearSnooze(for: bill.id) }
                                            .buttonStyle(.bordered)
                                        Button("Edit") { onEdit?(bill) }
                                            .buttonStyle(.bordered)
                                    }
                                } else {
                                    HStack(spacing: 6) {
                                        Text(format(date: bill.nextDueDate))
                                            .font(.caption)
                                            .foregroundStyle(bill.isOverdue ? .red : .secondary)
                                        Text(dueBadgeText(for: bill))
                                            .font(.caption.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(badgeColor(for: bill))
                                            .foregroundStyle(.white)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .opacity(section == .deferred ? 0.6 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .tag(bill.id)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onEdit?(bill) })
                    .contextMenu {
                        if section == .deferred {
                            Button("Clear Snooze") { store.clearSnooze(for: bill.id) }
                        }
                        Button(role: .destructive) {
                            deleteBills(ids: [bill.id])
                        } label: {
                            Text("Delete")
                        }
                    }
                }
                .onDelete { indexSet in
                    let ids = indexSet.map { filtered[$0].id }
                    deleteBills(ids: Array(ids))
                }
            }
            .searchable(text: $search)
        }
        .padding(.bottom)
        // Add sheet moved to the main toolbar in RootSplitView
        
    }

    private func deleteBills(ids: [UUID]) {
        store.bills.removeAll { ids.contains($0.id) }
        if let sel = store.selectedBillID, ids.contains(sel) { store.selectedBillID = nil }
    }
 
    private func format(amount: DecimalAmount) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = store.settings.displayCurrencyCode
        return nf.string(for: amount.value as NSDecimalNumber) ?? "\(amount.value)"
    }

    private func format(date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: date)
    }

    private func daysUntil(_ date: Date) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private func dueBadgeText(for bill: Bill) -> String {
        let d = daysUntil(bill.nextDueDate)
        if d == 0 { return "Due today" }
        if d < 0 { return "Overdue \(-d)d" }
        return "Due in \(d) days"
    }
    private func snoozeBadgeText(for bill: Bill) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: bill.snoozeUntil ?? Date())
        let days = cal.dateComponents([.day], from: today, to: end).day ?? 0
        if days <= 0 { return "Returns today" }
        if days == 1 { return "Returns tomorrow" }
        return "Returns in \(days) days"
    }

    private func badgeColor(for bill: Bill) -> Color {
        let d = daysUntil(bill.nextDueDate)
        if d == 0 { return .red }
        if d < 0 { return .red }
        if d <= 7 { return .yellow }
        return .blue
    }
 
    private func longDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .full
        return df.string(from: d)
    }
 
 
}
