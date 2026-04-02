import SwiftUI
import UniformTypeIdentifiers

struct HistoryListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var newestFirst: Bool = true
    @State private var kind: KindFilter = .all
    @State private var period: PeriodFilter = .monthly
    @State private var billCategoryFilter: Bill.Category? = nil
    @State private var incomeSourceFilter: Income.Source? = nil
    @State private var loadedCount: Int = 0
    private let pageSize: Int = 50
    private let initialMax: Int = 100
    @State private var expandedMonths: Set<String> = []
    private let windowDaysDefault: Int = 30
    @State private var isLoadingMore: Bool = false
    
    enum KindFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case bills = "Bills"
        case income = "Income"
        var id: String { rawValue }
    }
    enum PeriodFilter: String, CaseIterable, Identifiable {
        case weekly = "Weekly"
        case monthly = "Monthly"
        case yearly = "Yearly"
        var id: String { rawValue }
    }
    
    struct Item: Identifiable {
        enum Kind { case bill, income }
        let id = UUID()
        let date: Date
        let amount: DecimalAmount
        let title: String
        let subtitle: String
        let icon: String
        let kind: Kind
        let refID: UUID
    }
    
    private var itemsAll: [Item] {
        let now = Date()
        let cal = Calendar.current
        // Build a larger horizon, but we will page/collapse in UI.
        let past = cal.date(byAdding: .year, value: -5, to: now) ?? now
        var result: [Item] = []
        if kind != .income {
            for bill in store.bills {
                if let cat = billCategoryFilter, bill.category != cat { continue }
                for p in bill.payments where p.date >= past {
                    result.append(Item(date: p.date,
                                       amount: p.amount,
                                       title: bill.name,
                                       subtitle: "Bill • \(bill.category.rawValue.capitalized)",
                                       icon: bill.category.symbolName,
                                       kind: .bill,
                                       refID: bill.id))
                }
            }
        }
        if kind != .bills {
            for inc in store.incomes {
                if let src = incomeSourceFilter, inc.source != src { continue }
                for r in inc.receipts where r.date >= past {
                    result.append(Item(date: r.date,
                                       amount: r.amount,
                                       title: inc.name,
                                       subtitle: "Income • \(inc.source.rawValue.capitalized)",
                                       icon: symbol(for: inc.source),
                                       kind: .income,
                                       refID: inc.id))
                }
            }
        }
        if !search.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.subtitle.localizedCaseInsensitiveContains(search) }
        }
        return result.sorted { newestFirst ? $0.date > $1.date : $0.date < $1.date }
    }
    // Default "recent only": aim for last 30 days but ensure at least ~12 months coverage or up to 100 items
    private var initialLoadedCount: Int {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -windowDaysDefault, to: Date()) ?? Date()
        var count = 0
        var months: Set<String> = []
        for it in itemsAll {
            count += 1
            months.insert(monthKey(cal.dateComponents([.year, .month], from: it.date)))
            if it.date < cutoff && months.count >= 12 && count >= pageSize { break }
            if count >= initialMax { break }
        }
        if count == 0 { return min(itemsAll.count, initialMax) }
        return min(count, max(pageSize, initialMax))
    }
    private var itemsPaged: [Item] {
        let aligned = alignedCount(loadedCount)
        return Array(itemsAll.prefix(aligned))
    }
    
    private var grouped: [(key: DateComponents, items: [Item])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: itemsPaged) { item in
            cal.dateComponents([.year, .month], from: item.date)
        }
        let sortedKeys = dict.keys.sorted {
            let d1 = Calendar.current.date(from: $0) ?? Date.distantPast
            let d2 = Calendar.current.date(from: $1) ?? Date.distantPast
            return newestFirst ? d1 > d2 : d1 < d2
        }
        return sortedKeys.map { ($0, (dict[$0] ?? []).sorted { newestFirst ? $0.date > $1.date : $0.date < $1.date }) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transactions")
                    .font(.title2.bold())
                Spacer()
                Picker("", selection: $kind) {
                    ForEach(KindFilter.allCases) { k in Text(k.rawValue).tag(k) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Menu {
                    Section("Order") {
                        Picker("Order", selection: $newestFirst) {
                            Text("Newest").tag(true)
                            Text("Oldest").tag(false)
                        }
                    }
                    Section("Period") {
                        Picker("Period", selection: $period) {
                            ForEach(PeriodFilter.allCases) { p in Text(p.rawValue).tag(p) }
                        }
                    }
                    if kind == .bills {
                        Section("Category") {
                            Button("All Categories") { billCategoryFilter = nil }
                            Divider()
                            ForEach(Bill.Category.allCases, id: \.self) { c in
                                Button(c.rawValue.capitalized) { billCategoryFilter = c }
                            }
                        }
                    } else if kind == .income {
                        Section("Source") {
                            Button("All Sources") { incomeSourceFilter = nil }
                            Divider()
                            ForEach(Income.Source.allCases, id: \.self) { s in
                                Button(s.rawValue.capitalized) { incomeSourceFilter = s }
                            }
                        }
                    }
                    Divider()
                    Button("Reset Filters") {
                        newestFirst = true
                        period = .monthly
                        billCategoryFilter = nil
                        incomeSourceFilter = nil
                    }
                } label: {
                    Label("Sort & Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 6, pinnedViews: [.sectionHeaders]) {
                    ForEach(grouped, id: \.key) { group in
                        let key = monthKey(group.key)
                        Section {
                            if expandedMonths.contains(key) {
                                ForEach(group.items) { item in
                                    Button {
                                        switch item.kind {
                                        case .bill:
                                            store.selectedBillID = item.refID
                                            store.selectedDay = item.date
                                            store.selectedIncomeID = nil
                                            store.selectedIncomeDay = nil
                                        case .income:
                                            store.selectedIncomeID = item.refID
                                            store.selectedIncomeDay = item.date
                                            store.selectedBillID = nil
                                            store.selectedDay = nil
                                        }
                                    } label: {
                                        let cal = Calendar.current
                                        let isSelected: Bool = {
                                            switch item.kind {
                                            case .bill:
                                                guard store.selectedBillID == item.refID, let selDay = store.selectedDay else { return false }
                                                return cal.isDate(selDay, inSameDayAs: item.date)
                                            case .income:
                                                guard store.selectedIncomeID == item.refID, let selDay = store.selectedIncomeDay else { return false }
                                                return cal.isDate(selDay, inSameDayAs: item.date)
                                            }
                                        }()
                                        HStack(spacing: 10) {
                                            Image(systemName: item.icon)
                                                .font(.title3)
                                                .frame(width: 24)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.title).font(.headline)
                                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            VStack(alignment: .trailing, spacing: 2) {
                                                HStack(spacing: 4) {
                                                    let sign = (item.kind == .income) ? "+" : "–"
                                                    Text("\(sign) \(format(amount: item.amount))")
                                                        .font(Typography.amountFont(for: store.settings))
                                                        .foregroundStyle(item.kind == .income ? Color.green : Color.primary)
                                                }
                                                HStack(spacing: 6) {
                                                    Text(format(date: item.date)).font(.caption).foregroundStyle(.secondary)
                                                    if item.kind == .bill {
                                                        Text("✔ Paid").font(.caption).foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(isSelected ? Color.accentColor.opacity(0.35) : Color.clear)
                                        )
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } header: {
                            let isOpen = expandedMonths.contains(key)
                            let total = group.items.reduce(Decimal(0)) { acc, it in
                                let sign: Decimal = (it.kind == .income) ? 1 : -1
                                return acc + sign * it.amount.value
                            }
                            HStack {
                                HStack(spacing: 8) {
                                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                                    Text(monthTitle(group.key))
                                        .font(.headline)
                                        .fontWeight(isOpen ? .bold : .regular)
                                }
                                Spacer()
                                Text(currency(total))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(total >= 0 ? Color.green : Color.primary)
                                    .padding(.trailing, 2)
                            }
                            .padding(.horizontal)
                            .padding(.top, 4)
                            .padding(.bottom, 6)
                            .background(isOpen ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(alignment: .leading) {
                                if isOpen {
                                    Rectangle()
                                        .fill(Color.accentColor.opacity(0.7))
                                        .frame(width: 3)
                                        .cornerRadius(2)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { toggleMonth(key) }
                        }
                    }
                    if isLoadingMore {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading older months… This will take a moment.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)
                    }
                    if loadedCount < itemsAll.count {
                        Button("Load Older") { startLoadMore() }
                            .buttonStyle(.bordered)
                            .padding(.vertical, 10)
                    }
                }
            }
            .searchable(text: $search)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { exportCSV() } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .padding(.bottom)
        .onAppear {
            if loadedCount == 0 {
                loadedCount = initialLoadedCount
                if let firstKey = grouped.first.map({ monthKey($0.key) }) {
                    expandedMonths = [firstKey]
                }
            }
        }
    }
    
    private func format(amount: DecimalAmount) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = store.settings.displayCurrencyCode
        return nf.string(for: amount.value as NSDecimalNumber) ?? "\(amount.value)"
    }
    private func format(date: Date) -> String {
        let df = DateFormatter(); df.dateStyle = .medium; return df.string(from: date)
    }
    private func monthTitle(_ comps: DateComponents) -> String {
        var comps = comps
        comps.day = 1
        let d = Calendar.current.date(from: comps) ?? Date()
        let df = DateFormatter(); df.dateFormat = "LLLL yyyy"
        return df.string(from: d)
    }
    private func currency(_ value: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = store.settings.displayCurrencyCode
        return nf.string(for: value as NSDecimalNumber) ?? "\(value)"
    }
    private func monthKey(_ comps: DateComponents) -> String {
        "\(comps.year ?? 0)-\(String(format: "%02d", comps.month ?? 0))"
    }
    private func toggleMonth(_ key: String) {
        if expandedMonths.contains(key) { expandedMonths.remove(key) } else { expandedMonths.insert(key) }
    }
    private func loadMore() {
        loadedCount = min(loadedCount + pageSize, itemsAll.count)
    }
    private func loadMoreMonthAligned() {
        guard loadedCount < itemsAll.count else { return }
        if newestFirst {
            let start = alignedCount(loadedCount)
            if start >= itemsAll.count { return }
            let cal = Calendar.current
            let targetMonth = cal.dateComponents([.year, .month], from: itemsAll[start].date)
            var idx = start
            while idx < itemsAll.count &&
                    cal.dateComponents([.year, .month], from: itemsAll[idx].date) == targetMonth {
                idx += 1
            }
            loadedCount = idx
        } else {
            // Fallback to size-based growth for oldest-first view
            loadedCount = min(alignedCount(loadedCount + pageSize), itemsAll.count)
        }
    }
    private func startLoadMore() {
        isLoadingMore = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            loadMoreMonthAligned()
            isLoadingMore = false
        }
    }
    
    private func exportCSV() {
        var csv = "Date,Type,Name,Category/Source,Amount,Currency,Notes\n"
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        for item in itemsAll {
            let type = item.kind == .bill ? "Bill" : "Income"
            let dateStr = df.string(from: item.date)
            let amountStr = NSDecimalNumber(decimal: item.amount.value).stringValue
            let currency = item.amount.currencyCode
            var notes = ""
            if item.kind == .bill {
                if let bill = store.bills.first(where: { $0.id == item.refID }) { notes = bill.notes ?? "" }
            } else {
                if let inc = store.incomes.first(where: { $0.id == item.refID }) { notes = inc.notes ?? "" }
            }
            let safeName = item.title.replacingOccurrences(of: ",", with: " ")
            let safeSub = item.subtitle.replacingOccurrences(of: ",", with: " ")
            let safeNotes = notes.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: ",", with: " ")
            csv += "\(dateStr),\(type),\(safeName),\(safeSub),\(amountStr),\(currency),\(safeNotes)\n"
        }
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "PersonalFinances_Export_\(df.string(from: Date())).csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
        #endif
    }
    private func ensureMinimumMonthCoverage(minMonths: Int = 12) {
        // Attempt to ensure at least N months visible initially (without blocking UI)
        DispatchQueue.main.async {
            var seenMonths: Set<String> = []
            let cal = Calendar.current
            for it in self.itemsPaged {
                seenMonths.insert(self.monthKey(cal.dateComponents([.year, .month], from: it.date)))
            }
            var loops = 0
            while seenMonths.count < minMonths && self.loadedCount < self.itemsAll.count && loops < 5 {
                self.loadedCount = min(self.loadedCount + self.pageSize, self.itemsAll.count)
                for it in self.itemsPaged {
                    seenMonths.insert(self.monthKey(cal.dateComponents([.year, .month], from: it.date)))
                }
                loops += 1
            }
        }
    }
    private func alignedCount(_ count: Int) -> Int {
        let total = itemsAll.count
        if count <= 0 { return 0 }
        if count >= total { return total }
        let cal = Calendar.current
        var c = count
        let refDate = itemsAll[c - 1].date
        while c < total {
            let d = itemsAll[c].date
            if !cal.isDate(d, equalTo: refDate, toGranularity: .month) { break }
            c += 1
        }
        return c
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
}
