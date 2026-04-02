import SwiftUI

struct EditIncomeView: View {
    var income: Income
    var onSave: (Income) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var name: String
    @State private var amount: String
    @State private var payDate: Date
    @State private var recurrence: Recurrence
    @State private var source: Income.Source
    @State private var notes: String
    
    init(income: Income, onSave: @escaping (Income) -> Void) {
        self.income = income
        self.onSave = onSave
        _name = State(initialValue: income.name)
        _amount = State(initialValue: NSDecimalNumber(decimal: income.amount.value).stringValue)
        _payDate = State(initialValue: income.nextPayDate)
        _recurrence = State(initialValue: income.recurrence)
        _source = State(initialValue: income.source)
        _notes = State(initialValue: income.notes ?? "")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Income Name")
                .font(.title.bold())
            HStack(spacing: 8) {
                Image(systemName: symbol(for: source))
                    .font(.title2)
                TextField("Salary", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                Spacer()
                Picker("", selection: $source) {
                    ForEach(Income.Source.allCases, id: \.self) { s in
                        Text(s.rawValue.capitalized).tag(s)
                    }
                }
                .pickerStyle(.menu)
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Next Pay Date").frame(width: 140, alignment: .leading)
                    DatePicker("", selection: $payDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }
                GridRow {
                    Text("Repeat Interval").frame(width: 140, alignment: .leading)
                    Picker("", selection: $recurrence) {
                        ForEach(Recurrence.allCases, id: \.self) { r in
                            Text(r.rawValue.capitalized).tag(r)
                        }
                    }
                    .pickerStyle(.menu)
                }
                GridRow {
                    Text("Amount").frame(width: 140, alignment: .leading)
                    TextField("Amount", text: $amount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
                GridRow {
                    Text("Notes").frame(width: 140, alignment: .leading)
                    TextEditor(text: $notes)
                        .frame(minHeight: 72)
                        .padding(4)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                }
            }
            HStack {
                Button("Delete") {
                    if let idx = store.incomes.firstIndex(where: { $0.id == income.id }) {
                        store.incomes.remove(at: idx)
                    }
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") {
                    guard let dec = Decimal(string: amount), !name.isEmpty else { return }
                    var updated = income
                    updated.name = name
                    updated.amount = .init(currencyCode: income.amount.currencyCode, value: dec)
                    updated.source = source
                    updated.recurrence = recurrence
                    updated.nextPayDate = payDate
                    updated.notes = notes.isEmpty ? nil : notes
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(width: 640, height: 380)
        .onChange(of: source) { newSource in
            recurrence = newSource.defaultRecurrence
        }
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
