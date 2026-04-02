import SwiftUI

struct CalendarOverviewView: View {
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
        let padding = (firstWeekday + 5) % 7 // Monday first
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
                        let dot = dotColor(for: date)
                        let isSelected = store.selectedDay.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
                        Button {
                            store.selectedDay = isSelected ? nil : date
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
                                    .fill(
                                        isSelected
                                        ? Color.accentColor.opacity(0.35)
                                        : (Calendar.current.isDateInToday(date) ? Color.accentColor.opacity(0.12) : Color.clear)
                                    )
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
        let candidates = store.bills.filter { b in
            cal.isDate(b.nextDueDate, inSameDayAs: date)
            && !b.hiddenUntilEdited
            && !b.isSnoozedActive
            && !b.isPaidFor(date: b.nextDueDate)
        }
        guard !candidates.isEmpty else { return .clear }
        let daysList = candidates.map { cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: $0.nextDueDate)).day ?? 0 }
        if daysList.contains(0) { return .red }
        if daysList.contains(where: { $0 > 0 && $0 <= 7 }) { return .yellow }
        return .blue
    }
}
