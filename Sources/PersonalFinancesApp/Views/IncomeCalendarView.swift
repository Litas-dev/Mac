import SwiftUI

struct IncomeCalendarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var monthDate: Date = Date()
    var showHideControl: Bool = false
    var isVisible: Bool = true
    var onToggle: (() -> Void)? = nil
    
    private var monthDays: [Date?] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: monthDate) else { return [] }
        let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)) ?? cal.startOfDay(for: monthDate)
        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        let padding = (firstWeekday + 5) % 7
        var days: [Date?] = Array(repeating: nil, count: padding)
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(d)
            }
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title(for: monthDate)).font(.title3.bold())
                Spacer()
                Button { withAnimation { monthDate = calAdd(-1) } } label: { Image(systemName: "chevron.left") }
                Button { withAnimation { monthDate = calAdd(1) } } label: { Image(systemName: "chevron.right") }
                if showHideControl {
                    Button {
                        onToggle?()
                    } label: {
                        Image(systemName: isVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                }
            }
            .padding(.bottom, 4)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            HStack {
                ForEach(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"], id: \.self) { w in
                    Text(w).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, d in
                    if let date = d {
                        let isSelected = store.selectedIncomeDay.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
                        let dot = dotColor(for: date)
                        Button {
                            store.selectedIncomeDay = isSelected ? nil : date
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(Calendar.current.component(.day, from: date))")
                                    .frame(maxWidth: .infinity)
                                Circle()
                                    .fill(dot)
                                    .frame(width: 6, height: 6)
                                    .opacity(dot == .clear ? 0 : 1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .padding(6)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Color.accentColor.opacity(0.35) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private func title(for date: Date) -> String {
        let df = DateFormatter(); df.dateFormat = "LLLL yyyy"; return df.string(from: date)
    }
    private func calAdd(_ months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: monthDate) ?? monthDate
    }
    private func dotColor(for date: Date) -> Color {
        let cal = Calendar.current
        // Mark:
        // - Overdue (red) if nextPayDate was earlier and not received
        // - Today (orange) if due today and not received
        // - Upcoming (yellow) if later this month and not received
        let today = cal.startOfDay(for: Date())
        let day = cal.startOfDay(for: date)
        for inc in store.incomes {
            let isTargetDay = cal.isDate(inc.nextPayDate, inSameDayAs: date)
            if !isTargetDay { continue }
            let received = inc.receipts.contains { cal.isDate($0.date, inSameDayAs: inc.nextPayDate) }
            if received { continue }
            if day == today { return .orange }        // due today
            if day < today { return .red }            // overdue
            return .yellow                            // upcoming within the month
        }
        return .clear
    }
}
