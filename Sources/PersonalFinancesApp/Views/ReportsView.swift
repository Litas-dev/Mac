import SwiftUI
import Charts

struct ReportsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var mode: DataMode = .bills
    @State private var period: Period = .monthly
    @State private var selectedLabel: String? = nil
    @State private var hoveredLabel: String? = nil
    @State private var hoverLocation: CGPoint? = nil
    
    enum DataMode: String, CaseIterable, Identifiable {
        case bills = "Bills"
        case income = "Income"
        case ledgerExpenses = "Ledger Spend"
        case ledgerIncome = "Ledger Income"
        var id: String { rawValue }
    }
    enum Period: String, CaseIterable, Identifiable {
        case weekly = "Weekly"
        case monthly = "Monthly"
        case yearly = "Yearly"
        var id: String { rawValue }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header()
                insightStrip()
                barSection()
                pieSection()
            }
            .padding()
        }
        .dynamicTypeSize(store.dynamicTypeSize)
        .environment(\.controlSize, store.controlSize)
    }
    
    private func header() -> some View {
        HStack {
            Text("Reports")
                .font(.largeTitle.bold())
            Spacer()
            Button {
                store.generateSampleData()
            } label: {
                Label("Populate", systemImage: "plus.square.on.square")
            }
            .buttonStyle(.bordered)
            .help("Generate sample bills and incomes")
            Button {
                store.clearSampleData()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .help("Remove previously generated sample data")
            Button(role: .destructive) {
                store.resetAllData()
            } label: {
                Label("Reset All", systemImage: "trash.slash")
            }
            .buttonStyle(.borderedProminent)
            .help("Delete all bills and incomes")
            Picker("", selection: $mode) {
                ForEach(DataMode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            Picker("", selection: $period) {
                ForEach(Period.allCases) { p in Text(p.rawValue).tag(p) }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
        }
        .padding(.bottom, 4)
    }
    
    private func insightStrip() -> some View {
        let idx = selectedIndex() ?? (recentBins().count - 1)
        let curr = amountForBin(index: idx)
        let prev = amountForBin(index: idx - 1)
        let delta = curr - prev
        let pct = (prev != 0) ? (delta / prev) : 0
        return GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                // Line 1: Primary
                let pctText = String(format: "%.0f%%", abs(pct) * 100)
                let primary = "\(isSpendingMode(mode) ? "Spending" : "Income"): \(currency(from: Decimal(curr)))"
                Text(primary)
                    .font(.title3.weight(.semibold).monospacedDigit())
                // Lines 2..N: concise bullets
                let unit = period == .monthly ? "month" : period == .weekly ? "week" : "year"
                let arrow = (delta < 0) ? "↓" : (delta > 0 ? "↑" : "•")
                if prev != 0 && delta != 0 {
                    Text("\(arrow) \(delta < 0 ? "–" : "+")\(pctText) vs last \(unit)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                // Streak
                let streakUp = streakCount(up: true, idx: idx)
                let streakDown = streakCount(up: false, idx: idx)
                if streakDown >= 3 {
                    Text("↓ \(streakDown)-\(unit) declining trend")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if streakUp >= 3 {
                    Text("↑ \(streakUp)-\(unit) rising trend")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    private func streakCount(up: Bool, idx: Int) -> Int {
        var s = 1
        var i = idx
        while i - 1 >= 0 {
            let a = amountForBin(index: i)
            let b = amountForBin(index: i - 1)
            if up ? (a > b) : (a < b) {
                s += 1; i -= 1
            } else { break }
        }
        return s
    }
    
    private func barSection() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(mode.rawValue) Over Time").font(.headline)
                barChart()
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6))
                }
                .frame(height: 220)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: mode)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: period)
                // Range Total intentionally omitted (low decision value)
                if selectedLabel != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        let selVal = selectedRangeTotal()
                        let prevVal = previousRangeTotal()
                        let ch = selVal - prevVal
                        let pct = prevVal == 0 ? Decimal(0) : ch / prevVal
                        HStack {
                            Text("\(selectedTitle()):")
                            Spacer()
                            Text(currency(from: selVal)).monospacedDigit()
                        }
                        .font(.subheadline)
                        HStack {
                            Text("Previous:")
                            Spacer()
                            Text(currency(from: prevVal)).monospacedDigit()
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        let sign = (ch >= 0) ? "+" : "–"
                        HStack {
                            Text("Change:")
                            Spacer()
                            Text("\(sign)\(currency(from: abs(ch))) (\(sign)\(percentageString(from: abs(pct))))")
                                .monospacedDigit()
                                .foregroundStyle(ch >= 0 ? Color.green : Color.red)
                        }
                        .font(.footnote)
                        Button("Clear Selection") { selectedLabel = nil }
                            .buttonStyle(.bordered)
                            .padding(.top, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func pieSection() -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(mode.rawValue) by Category").font(.headline)
                categoryBars()
                .animation(.easeOut(duration: 0.3), value: mode)
                .animation(.easeOut(duration: 0.3), value: period)
                Divider()
                HStack {
                    Text("Period Total:")
                    Spacer()
                    Text(currency(from: currentPeriodTotal()))
                        .font(.headline.monospacedDigit())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func categoryBars() -> some View {
        let slices = pie()
        let total = max(0.0001, slices.reduce(0.0) { $0 + $1.amount })
        let maxVal = max(0.0001, slices.map { $0.amount }.max() ?? 0)
        let maxBarFactor: CGFloat = 0.90
        let pctColWidth: CGFloat = 56
        let amtColWidth: CGFloat = 140
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(slices.enumerated()), id: \.offset) { idx, s in
                let isHover = false
                VStack(spacing: 6) {
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(color(for: s.label).opacity(0.8))
                                .saturation(0.85)
                                .frame(width: 8, height: 8)
                            Text(s.label)
                                .font(idx == 0 ? .subheadline.weight(.semibold) : .subheadline)
                                .foregroundStyle(.primary.opacity(0.95))
                        }
                        Spacer(minLength: 8)
                        let pct = s.amount / total
                        Text(percentageString(from: Decimal(pct)))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary.opacity(0.9))
                            .frame(width: pctColWidth, alignment: .trailing)
                        Text(currency(fromDouble: s.amount))
                        .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary.opacity(0.95))
                            .frame(width: amtColWidth, alignment: .trailing)
                    }
                    GeometryReader { geo in
                        let fullWidth = geo.size.width * maxBarFactor
                        let w = max(0, fullWidth * CGFloat(s.amount / maxVal))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.12))
                                .frame(width: fullWidth)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(color(for: s.label).opacity(0.8))
                                .saturation(0.85)
                                .frame(width: w)
                        }
                    }
                    .frame(height: 10)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
                .padding(.trailing, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Color.clear)
                )
                .onHover { _ in }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func barChart() -> some View {
        let pts: [Point] = series()
        return Chart {
            ForEach(Array(pts.enumerated()), id: \.offset) { _, point in
                BarMark(
                    x: .value("Period", point.label),
                    y: .value("Amount", point.amount)
                )
                .foregroundStyle(Color.accentColor)
                .opacity(selectedLabel == nil || selectedLabel == point.label ? 1.0 : 0.35)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { val in
                                let plot = geo[proxy.plotAreaFrame]
                                let x = val.location.x - plot.origin.x
                                let w = max(plot.size.width, 1)
                                let ratio = max(0, min(1, x / w))
                                let count = max(pts.count, 1)
                                let idx = min(count - 1, max(0, Int(CGFloat(count) * ratio)))
                                selectedLabel = pts[idx].label
                            }
                    )
            }
        }
    }
    
    private func pieChart() -> some View {
        let slices: [Slice] = pie()
        let total = max(0.0001, slices.reduce(0.0) { $0 + $1.amount })
        return Chart {
            ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                let isHovered = hoveredLabel == slice.label
                SectorMark(
                    angle: .value("Amount", slice.amount),
                    innerRadius: .ratio(isHovered ? 0.52 : 0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(color(for: slice.label))
                .opacity(hoveredLabel == nil || isHovered ? 1.0 : 0.45)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            guard let pf = proxy.plotFrame else {
                                hoveredLabel = nil
                                hoverLocation = nil
                                return
                            }
                            let plot = geo[pf]
                            let center = CGPoint(x: plot.midX, y: plot.midY)
                            let rMax = min(plot.size.width, plot.size.height) / 2.0
                            let rMin = rMax * 0.55 - 8
                            let rMaxTol = rMax + 8
                            let p = loc
                            let dx = p.x - center.x
                            let dy = center.y - p.y
                            let r = hypot(dx, dy)
                            guard r >= rMin && r <= rMaxTol else {
                                hoveredLabel = nil
                                hoverLocation = nil
                                return
                            }
                            var angle = atan2(dy, dx) // -pi...pi from +X (3 o'clock)
                            if angle < 0 { angle += .pi * 2 }
                            let degrees = fmod(angle * 180 / .pi, 360)
                            // Choose nearest slice center among multiple orientation guesses to avoid mapping mismatch
                            func nearestLabel(for offset: Double, clockwise: Bool) -> (String, Double) {
                                var accum: Double = 0
                                var bestLabel: String = slices.first?.label ?? ""
                                var bestDist: Double = .infinity
                                for s in slices {
                                    let frac = s.amount / total
                                    // Clockwise centers from +X
                                    let center = (accum + frac / 2) * 360
                                    let centered = clockwise ? center : (360 - center)
                                    let centerDeg = fmod(centered + offset, 360)
                                    // circular distance
                                    let d = abs(fmod((degrees - centerDeg + 540), 360) - 180)
                                    if d < bestDist {
                                        bestDist = d
                                        bestLabel = s.label
                                    }
                                    accum += frac
                                }
                                return (bestLabel, bestDist)
                            }
                            let candidates = [
                                nearestLabel(for: 0, clockwise: true),
                                nearestLabel(for: 270, clockwise: true),
                                nearestLabel(for: 0, clockwise: false),
                                nearestLabel(for: 270, clockwise: false),
                            ]
                            let found = candidates.min(by: { $0.1 < $1.1 })?.0
                            withAnimation(.easeOut(duration: 0.18)) {
                                hoveredLabel = found
                                hoverLocation = loc
                            }
                        case .ended:
                            withAnimation(.easeOut(duration: 0.1)) {
                                hoveredLabel = nil
                                hoverLocation = nil
                            }
                        }
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if let hovered = hoveredLabel, let pos = hoverLocation {
                let s = slices.first(where: { $0.label == hovered })
                if let s {
                    let pct = total == 0 ? 0 : s.amount / total
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hovered).font(.caption.bold())
                        Text(currency(fromDouble: s.amount)).font(.caption.monospacedDigit())
                        Text(percentageString(from: Decimal(pct))).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1)))
                    .position(x: pos.x + 12, y: max(12, pos.y - 12))
                    .transition(.opacity)
                }
            }
        }
    }
    
    private func currency(from decimal: Decimal) -> String {
        let nf = NumberFormatter(); nf.numberStyle = .currency
        nf.currencyCode = store.settings.displayCurrencyCode
        return nf.string(for: decimal as NSDecimalNumber) ?? "\(decimal)"
    }
    private func currency(fromDouble d: Double) -> String {
        currency(from: Decimal(d))
    }
    
    private func recentBins() -> [(start: Date, label: String)] {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .weekly:
            let count = 12
            return (0..<count).map { i in
                let base = cal.startOfDay(for: now)
                let start = cal.date(byAdding: .weekOfYear, value: -(count - 1 - i), to: base) ?? base
                let label = shortWeekLabel(for: start)
                return (start, label)
            }
        case .monthly:
            let count = 12
            return (0..<count).map { i in
                let d = cal.date(byAdding: .month, value: -(count - 1 - i), to: now) ?? now
                let comps = cal.dateComponents([.year, .month], from: d)
                let start = cal.date(from: comps) ?? cal.startOfDay(for: d)
                let label = monthLabel(for: start)
                return (start, label)
            }
        case .yearly:
            let count = 5
            return (0..<count).map { i in
                let d = cal.date(byAdding: .year, value: -(count - 1 - i), to: now) ?? now
                let comps = cal.dateComponents([.year], from: d)
                let start = cal.date(from: comps) ?? cal.startOfDay(for: d)
                let label = yearLabel(for: start)
                return (start, label)
            }
        }
    }
    
    private func endOfBin(from start: Date) -> Date {
        let cal = Calendar.current
        switch period {
        case .weekly:
            return cal.date(byAdding: .day, value: 7, to: start) ?? start
        case .monthly:
            return cal.date(byAdding: .month, value: 1, to: start) ?? start
        case .yearly:
            return cal.date(byAdding: .year, value: 1, to: start) ?? start
        }
    }
    
    private struct Point: Identifiable {
        let id = UUID()
        let label: String
        let amount: Double
    }
    private struct Slice: Identifiable {
        let id = UUID()
        let label: String
        let amount: Double
    }
    
    private func series() -> [Point] {
        let bins = recentBins()
        switch mode {
        case .bills:
            return bins.map { bin in
                let sum = store.bills.reduce(Decimal(0)) { partial, bill in
                    let s = bill.payments.filter { p in
                        p.date >= bin.start && p.date < endOfBin(from: bin.start)
                    }.reduce(Decimal(0)) { $0 + $1.amount.value }
                    return partial + s
                }
                return Point(label: bin.label, amount: (sum as NSDecimalNumber).doubleValue)
            }
        case .income:
            return bins.map { bin in
                let sum = store.incomes.reduce(Decimal(0)) { partial, inc in
                    let s = inc.receipts.filter { r in
                        r.date >= bin.start && r.date < endOfBin(from: bin.start)
                    }.reduce(Decimal(0)) { $0 + $1.amount.value }
                    return partial + s
                }
                return Point(label: bin.label, amount: (sum as NSDecimalNumber).doubleValue)
            }
        case .ledgerExpenses:
            return bins.map { bin in
                let end = endOfBin(from: bin.start)
                let sum = store.transactions
                    .filter { $0.kind == .expense && $0.date >= bin.start && $0.date < end }
                    .reduce(Decimal(0)) { $0 + $1.amount.value }
                return Point(label: bin.label, amount: (sum as NSDecimalNumber).doubleValue)
            }
        case .ledgerIncome:
            return bins.map { bin in
                let end = endOfBin(from: bin.start)
                let sum = store.transactions
                    .filter { $0.kind == .income && $0.date >= bin.start && $0.date < end }
                    .reduce(Decimal(0)) { $0 + $1.amount.value }
                return Point(label: bin.label, amount: (sum as NSDecimalNumber).doubleValue)
            }
        }
    }
    
    private func total() -> Decimal {
        let d = series().reduce(0.0) { $0 + $1.amount }
        return Decimal(d)
    }
    
    private func currentPeriodRange() -> (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .weekly:
            let start = cal.startOfDay(for: now)
            return (start, cal.date(byAdding: .day, value: 7, to: start) ?? start)
        case .monthly:
            let comps = cal.dateComponents([.year, .month], from: now)
            let start = cal.date(from: comps) ?? cal.startOfDay(for: now)
            return (start, cal.date(byAdding: .month, value: 1, to: start) ?? start)
        case .yearly:
            let comps = cal.dateComponents([.year], from: now)
            let start = cal.date(from: comps) ?? cal.startOfDay(for: now)
            return (start, cal.date(byAdding: .year, value: 1, to: start) ?? start)
        }
    }
    
    private func pie() -> [Slice] {
        let range = selectedRange() ?? currentPeriodRange()
        switch mode {
        case .bills:
            var byCategory: [Bill.Category: Decimal] = [:]
            for bill in store.bills {
                let sum = bill.payments.filter { $0.date >= range.start && $0.date < range.end }
                    .reduce(Decimal(0)) { $0 + $1.amount.value }
                guard sum > 0 else { continue }
                byCategory[bill.category, default: 0] += sum
            }
            return byCategory.map { Slice(label: $0.key.rawValue.capitalized, amount: ($0.value as NSDecimalNumber).doubleValue) }
                .sorted { $0.amount > $1.amount }
        case .income:
            var bySource: [Income.Source: Decimal] = [:]
            for inc in store.incomes {
                let sum = inc.receipts.filter { $0.date >= range.start && $0.date < range.end }
                    .reduce(Decimal(0)) { $0 + $1.amount.value }
                guard sum > 0 else { continue }
                bySource[inc.source, default: 0] += sum
            }
            return bySource.map { Slice(label: $0.key.rawValue.capitalized, amount: ($0.value as NSDecimalNumber).doubleValue) }
                .sorted { $0.amount > $1.amount }
        case .ledgerExpenses:
            var byLabel: [String: Decimal] = [:]
            for t in store.transactions {
                guard t.kind == .expense else { continue }
                guard t.date >= range.start && t.date < range.end else { continue }
                let label = (t.customCategoryName?.isEmpty == false) ? (t.customCategoryName ?? "Other") : (t.category?.rawValue.capitalized ?? "Other")
                byLabel[label, default: 0] += t.amount.value
            }
            return byLabel.map { Slice(label: $0.key, amount: ($0.value as NSDecimalNumber).doubleValue) }
                .sorted { $0.amount > $1.amount }
        case .ledgerIncome:
            var byLabel: [String: Decimal] = [:]
            for t in store.transactions {
                guard t.kind == .income else { continue }
                guard t.date >= range.start && t.date < range.end else { continue }
                let label = t.payee ?? "Income"
                byLabel[label, default: 0] += t.amount.value
            }
            return byLabel.map { Slice(label: $0.key, amount: ($0.value as NSDecimalNumber).doubleValue) }
                .sorted { $0.amount > $1.amount }
        }
    }
    
    private func currentPeriodTotal() -> Decimal {
        let sum = pie().reduce(0.0) { $0 + $1.amount }
        return Decimal(sum)
    }
    
    private func selectedRangeTotal() -> Decimal {
        guard let r = selectedRange() else { return 0 }
        switch mode {
        case .bills:
            let sum = store.bills.flatMap { $0.payments }.filter { $0.date >= r.start && $0.date < r.end }
                .reduce(Decimal(0)) { $0 + $1.amount.value }
            return sum
        case .income:
            let sum = store.incomes.flatMap { $0.receipts }.filter { $0.date >= r.start && $0.date < r.end }
                .reduce(Decimal(0)) { $0 + $1.amount.value }
            return sum
        case .ledgerExpenses:
            return store.transactions.filter { $0.kind == .expense && $0.date >= r.start && $0.date < r.end }
                .reduce(Decimal(0)) { $0 + $1.amount.value }
        case .ledgerIncome:
            return store.transactions.filter { $0.kind == .income && $0.date >= r.start && $0.date < r.end }
                .reduce(Decimal(0)) { $0 + $1.amount.value }
        }
    }
    
    private func previousRangeTotal() -> Decimal {
        guard let r = selectedRange() ?? defaultCurrentRange() else { return 0 }
        let cal = Calendar.current
        let prevEnd: Date
        let prevStart: Date
        switch period {
        case .weekly:
            prevEnd = r.start
            prevStart = cal.date(byAdding: .day, value: -7, to: prevEnd) ?? prevEnd
        case .monthly:
            prevEnd = r.start
            prevStart = cal.date(byAdding: .month, value: -1, to: prevEnd) ?? prevEnd
        case .yearly:
            prevEnd = r.start
            prevStart = cal.date(byAdding: .year, value: -1, to: prevEnd) ?? prevEnd
        }
        switch mode {
        case .bills:
            return store.bills.flatMap { $0.payments }.filter { $0.date >= prevStart && $0.date < prevEnd }
                .reduce(Decimal(0)) { $0 + $1.amount.value }
        case .income:
            return store.incomes.flatMap { $0.receipts }.filter { $0.date >= prevStart && $0.date < prevEnd }
                .reduce(Decimal(0)) { $0 + $1.amount.value }
        case .ledgerExpenses:
            return store.transactions.filter { $0.kind == .expense && $0.date >= prevStart && $0.date < prevEnd }
                .reduce(Decimal(0)) { $0 + $1.amount.value }
        case .ledgerIncome:
            return store.transactions.filter { $0.kind == .income && $0.date >= prevStart && $0.date < prevEnd }
                .reduce(Decimal(0)) { $0 + $1.amount.value }
        }
    }
    
    private func selectedRange() -> (start: Date, end: Date)? {
        guard let sel = selectedLabel else { return nil }
        if let bin = recentBins().first(where: { $0.label == sel }) {
            return (bin.start, endOfBin(from: bin.start))
        }
        return nil
    }
    private func defaultCurrentRange() -> (start: Date, end: Date)? {
        let bins = recentBins()
        guard let last = bins.last else { return nil }
        return (last.start, endOfBin(from: last.start))
    }
    private func selectedTitle() -> String {
        if let r = selectedRange() {
            switch period {
            case .weekly:
                let week = Calendar.current.component(.weekOfYear, from: r.start)
                return "Week \(week)"
            case .monthly:
                let df = DateFormatter(); df.dateFormat = "LLLL"
                return df.string(from: r.start)
            case .yearly:
                let df = DateFormatter(); df.dateFormat = "yyyy"
                return df.string(from: r.start)
            }
        } else {
            return period == .monthly ? "This Month" : period == .weekly ? "This Week" : "This Year"
        }
    }
    
    private func monthLabel(for date: Date) -> String {
        let df = DateFormatter(); df.dateFormat = "MMM"
        return df.string(from: date)
    }
    private func yearLabel(for date: Date) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy"
        return df.string(from: date)
    }
    private func shortWeekLabel(for date: Date) -> String {
        let df = DateFormatter(); df.dateFormat = "w/yy"
        return df.string(from: date)
    }
    
    private func color(for label: String) -> Color {
        let key = label.lowercased()
        switch key {
        // Bills
        case "subscriptions": return Color.purple
        case "utilities":     return Color.blue
        case "housing":       return Color.brown
        case "insurance":     return Color.cyan
        case "taxes":         return Color.orange
        case "transport":     return Color.green
        case "other":         return Color.gray
        // Income
        case "salary":        return Color.green
        case "freelance":     return Color.teal
        case "rental":        return Color.indigo
        case "investment":    return Color.pink
        default:
            let hash = abs(label.hashValue)
            let hue = Double(hash % 256) / 256.0
            return Color(hue: hue, saturation: 0.6, brightness: 0.9)
        }
    }
    
    // MARK: - Insight helpers
    private func selectedIndex() -> Int? {
        guard let sel = selectedLabel else { return nil }
        let bins = recentBins()
        return bins.firstIndex(where: { $0.label == sel })
    }
    private func amountForBin(index: Int) -> Double {
        let pts = series()
        guard index >= 0 && index < pts.count else { return 0 }
        return pts[index].amount
    }
    private func highestBin() -> (Int, Double) {
        let pts = series()
        guard let maxVal = pts.map({ $0.amount }).max(),
              let idx = pts.firstIndex(where: { $0.amount == maxVal }) else { return (0, 0) }
        return (idx, maxVal)
    }
    private func lowestBin() -> (Int, Double) {
        let pts = series()
        guard let minVal = pts.map({ $0.amount }).min(),
              let idx = pts.firstIndex(where: { $0.amount == minVal }) else { return (0, 0) }
        return (idx, minVal)
    }
    private func labelForBin(_ label: String) -> String {
        label
    }
    private func insightMessages() -> [String] {
        let pts = series().map { $0.amount }
        guard !pts.isEmpty else { return [] }
        let idx = selectedIndex() ?? (pts.count - 1)
        let curr = amountForBin(index: idx)
        let prev = amountForBin(index: idx - 1)
        let unit = period == .monthly ? "month" : period == .weekly ? "week" : "year"
        let noun = isSpendingMode(mode) ? "Spending" : "Income"
        var out: [String] = []
        
        // 1) Month-over-month change
        if prev > 0 {
            let change = curr - prev
            let pct = change / prev
            if pct >= 0.15 {
                out.append("\(noun) is up \(String(format: "%.0f%%", pct * 100)) vs last \(unit)")
            } else if pct <= -0.15 {
                out.append("\(noun) is down \(String(format: "%.0f%%", abs(pct) * 100)) vs last \(unit)")
            } else if abs(pct) < 0.05 {
                out.append("\(noun) roughly flat vs last \(unit)")
            }
        }
        
        // 2) Streak detection (3+ up or down in a row)
        func streak(up: Bool) -> Int {
            var s = 1
            var i = idx
            while i - 1 >= 0 {
                let a = amountForBin(index: i)
                let b = amountForBin(index: i - 1)
                if up ? (a > b) : (a < b) {
                    s += 1
                    i -= 1
                } else { break }
            }
            return s
        }
        let upStreak = streak(up: true)
        let downStreak = streak(up: false)
        if upStreak >= 3 {
            out.append("\(noun) on a \(upStreak)-\(unit) rising streak")
        } else if downStreak >= 3 {
            out.append("\(noun) on a \(downStreak)-\(unit) falling streak")
        }
        
        // 3) Highest/lowest in last 6 periods
        let last6 = Array(pts.suffix(6))
        if last6.count >= 2 {
            if let max6 = last6.max(), curr >= max6 {
                out.append("Highest \(noun.lowercased()) in last 6 \(unit)s")
            }
            if let min6 = last6.min(), curr <= min6 {
                out.append("Lowest \(noun.lowercased()) in last 6 \(unit)s")
            }
            // 4) Above/below 6-period average by threshold
            let avg6 = last6.reduce(0, +) / Double(last6.count)
            if avg6 > 0 {
                let pctToAvg = (curr - avg6) / avg6
                if pctToAvg >= 0.1 {
                    out.append("\(noun) above \(6)-\(unit) average by \(String(format: "%.0f%%", pctToAvg * 100))")
                } else if pctToAvg <= -0.1 {
                    out.append("\(noun) below \(6)-\(unit) average by \(String(format: "%.0f%%", abs(pctToAvg) * 100))")
                }
            }
        }
        
        // De-duplicate while preserving order and keep at most 3
        var seen = Set<String>()
        let dedup = out.filter { seen.insert($0).inserted }
        return Array(dedup.prefix(3))
    }
    private func topCategoryLine() -> String? {
        let slices = pie()
        guard let top = slices.max(by: { $0.amount < $1.amount }), top.amount > 0 else { return nil }
        let total = slices.reduce(0.0) { $0 + $1.amount }
        let pct = total == 0 ? 0 : top.amount / total
        var line = "Top category: \(top.label) (\(percentageString(from: Decimal(pct))))"
        if let prevRange = previousOfSelectedOrCurrent() {
            let prevSlices = pie(in: prevRange)
            let prevTotal = prevSlices.reduce(0.0) { $0 + $1.amount }
            if let prevTop = prevSlices.first(where: { $0.label == top.label }), prevTotal > 0 {
                let prevPct = prevTop.amount / prevTotal
                let diff = pct - prevPct
                if abs(diff) >= 0.05 {
                    let sign = diff >= 0 ? "increased" : "decreased"
                    line += " — \(sign) by \(percentageString(from: Decimal(abs(diff))))"
                }
            }
        }
        return line
    }
    private func pie(in range: (start: Date, end: Date)) -> [Slice] {
        switch mode {
        case .bills:
            var byCategory: [Bill.Category: Decimal] = [:]
            for bill in store.bills {
                let sum = bill.payments.filter { $0.date >= range.start && $0.date < range.end }
                    .reduce(Decimal(0)) { $0 + $1.amount.value }
                guard sum > 0 else { continue }
                byCategory[bill.category, default: 0] += sum
            }
            return byCategory.map { Slice(label: $0.key.rawValue.capitalized, amount: ($0.value as NSDecimalNumber).doubleValue) }
        case .income:
            var bySource: [Income.Source: Decimal] = [:]
            for inc in store.incomes {
                let sum = inc.receipts.filter { $0.date >= range.start && $0.date < range.end }
                    .reduce(Decimal(0)) { $0 + $1.amount.value }
                guard sum > 0 else { continue }
                bySource[inc.source, default: 0] += sum
            }
            return bySource.map { Slice(label: $0.key.rawValue.capitalized, amount: ($0.value as NSDecimalNumber).doubleValue) }
        case .ledgerExpenses:
            var byLabel: [String: Decimal] = [:]
            for t in store.transactions {
                guard t.kind == .expense else { continue }
                guard t.date >= range.start && t.date < range.end else { continue }
                let label = (t.customCategoryName?.isEmpty == false) ? (t.customCategoryName ?? "Other") : (t.category?.rawValue.capitalized ?? "Other")
                byLabel[label, default: 0] += t.amount.value
            }
            return byLabel.map { Slice(label: $0.key, amount: ($0.value as NSDecimalNumber).doubleValue) }
        case .ledgerIncome:
            var byLabel: [String: Decimal] = [:]
            for t in store.transactions {
                guard t.kind == .income else { continue }
                guard t.date >= range.start && t.date < range.end else { continue }
                let label = t.payee ?? "Income"
                byLabel[label, default: 0] += t.amount.value
            }
            return byLabel.map { Slice(label: $0.key, amount: ($0.value as NSDecimalNumber).doubleValue) }
        }
    }
    
    private func isSpendingMode(_ mode: DataMode) -> Bool {
        switch mode {
        case .bills, .ledgerExpenses:
            return true
        case .income, .ledgerIncome:
            return false
        }
    }
    private func previousOfSelectedOrCurrent() -> (start: Date, end: Date)? {
        let r = selectedRange() ?? defaultCurrentRange()
        guard let r else { return nil }
        let cal = Calendar.current
        switch period {
        case .weekly: return (cal.date(byAdding: .day, value: -7, to: r.start) ?? r.start, r.start)
        case .monthly: return (cal.date(byAdding: .month, value: -1, to: r.start) ?? r.start, r.start)
        case .yearly: return (cal.date(byAdding: .year, value: -1, to: r.start) ?? r.start, r.start)
        }
    }
    private func percentageString(from decimal: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .percent
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 0
        let ns = decimal as NSDecimalNumber
        return nf.string(from: ns) ?? "\(ns.doubleValue * 100)%"
    }
}
