import SwiftUI

struct MiniMonthPicker: View {
    @Binding var date: Date
    var onSelect: (Date) -> Void
    @State private var monthDate: Date
    
    init(date: Binding<Date>, onSelect: @escaping (Date) -> Void) {
        _date = date
        self.onSelect = onSelect
        _monthDate = State(initialValue: Calendar.current.startOfDay(for: date.wrappedValue))
    }
    
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
                Text(title(for: monthDate)).font(.headline)
                Spacer()
                Button { withAnimation { monthDate = addMonths(-1) } } label: { Image(systemName: "chevron.left") }
                Button { withAnimation { monthDate = addMonths(1) } } label: { Image(systemName: "chevron.right") }
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            HStack {
                ForEach(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"], id: \.self) { w in
                    Text(w).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, d in
                    if let day = d {
                        let isSelected = Calendar.current.isDate(day, inSameDayAs: date)
                        Button {
                            date = day
                            onSelect(day)
                        } label: {
                            Text("\(Calendar.current.component(.day, from: day))")
                                .frame(maxWidth: .infinity)
                                .padding(6)
                                .frame(height: 36)
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? Color.accentColor.opacity(0.35) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 300)
    }
    
    private func title(for date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "LLLL yyyy"
        return df.string(from: date)
    }
    private func addMonths(_ m: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: m, to: monthDate) ?? monthDate
    }
}
