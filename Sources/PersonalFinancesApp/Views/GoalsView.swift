import SwiftUI

struct GoalsListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search: String = ""
    @State private var editing: Goal? = nil
    @State private var showingNew: Bool = false
    
    private var filtered: [Goal] {
        var items = store.goals.filter { !$0.archived }
        if !search.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(search) || ($0.notes?.localizedCaseInsensitiveContains(search) ?? false) }
        }
        return items.sorted(by: { $0.name < $1.name })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Goals")
                    .font(.title2.bold())
                Spacer()
                Button("Add") { showingNew = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .top])
            
            List(selection: $store.selectedGoalID) {
                ForEach(filtered) { g in
                    Button { store.selectedGoalID = g.id } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "target")
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(g.name).font(.headline)
                                ProgressView(value: progress(g))
                                    .progressViewStyle(.linear)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(currency(g.savedAmount.value, code: g.savedAmount.currencyCode) + " / " + currency(g.targetAmount.value, code: g.targetAmount.currencyCode))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(Int((progress(g) * 100).rounded()))%")
                                    .monospacedDigit()
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit") { editing = g }
                        Button("Archive") {
                            var updated = g
                            updated.archived = true
                            store.update(updated)
                        }
                    }
                    .tag(g.id)
                }
            }
            .searchable(text: $search)
        }
        .sheet(item: $editing) { g in
            EditGoalView(goal: g) { updated in
                store.update(updated)
                editing = nil
            }
        }
        .sheet(isPresented: $showingNew) {
            let code = store.settings.displayCurrencyCode
            let new = Goal(
                name: "",
                targetAmount: .init(currencyCode: code, value: 0),
                savedAmount: .init(currencyCode: code, value: 0),
                targetDate: nil,
                notes: nil,
                archived: false
            )
            EditGoalView(goal: new) { created in
                store.addGoal(created)
                showingNew = false
            }
        }
    }
    
    private func progress(_ g: Goal) -> Double {
        if g.targetAmount.value <= 0 { return 0 }
        let p = (g.savedAmount.value / g.targetAmount.value).doubleValueRounded(3)
        return max(0, min(1, p))
    }
    
    private func currency(_ decimal: Decimal, code: String) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = code
        return nf.string(for: decimal as NSDecimalNumber) ?? "\(decimal)"
    }
}

struct GoalsDetailView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: Goal? = nil
    @State private var addAmount: Decimal = 0
    
    var body: some View {
        if let g = store.selectedGoal {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name).font(.title2.bold())
                            if let d = g.targetDate {
                                Text("Target: " + shortDate(d))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Edit") { editing = g }
                            .buttonStyle(.borderedProminent)
                    }
                    
                    Divider()
                    
                    let code = g.targetAmount.currencyCode
                    HStack {
                        Text("Saved").font(.headline)
                        Spacer()
                        Text(currency(g.savedAmount.value, code: code)).monospacedDigit()
                    }
                    HStack {
                        Text("Target").font(.headline)
                        Spacer()
                        Text(currency(g.targetAmount.value, code: code)).monospacedDigit()
                    }
                    ProgressView(value: progress(g))
                        .progressViewStyle(.linear)
                    
                    Divider()
                    
                    HStack(spacing: 10) {
                        TextField("Add to saved", value: $addAmount, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                        Button("Apply") {
                            var updated = g
                            updated.savedAmount = .init(currencyCode: code, value: g.savedAmount.value + addAmount)
                            store.update(updated)
                            addAmount = 0
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(addAmount == 0)
                    }
                    
                    if let notes = g.notes, !notes.isEmpty {
                        Divider()
                        Text("Notes").font(.headline)
                        Text(notes).foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        store.deleteGoal(id: g.id)
                    } label: {
                        Text("Delete Goal")
                    }
                }
                .padding()
            }
            .sheet(item: $editing) { item in
                EditGoalView(goal: item) { updated in
                    store.update(updated)
                    editing = nil
                }
            }
        } else {
            VStack {
                Text("Select a goal")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func progress(_ g: Goal) -> Double {
        if g.targetAmount.value <= 0 { return 0 }
        let p = (g.savedAmount.value / g.targetAmount.value).doubleValueRounded(3)
        return max(0, min(1, p))
    }
    
    private func shortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: date)
    }
    
    private func currency(_ decimal: Decimal, code: String) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = code
        return nf.string(for: decimal as NSDecimalNumber) ?? "\(decimal)"
    }
}

private struct EditGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var goal: Goal
    @State private var targetValue: Decimal
    @State private var savedValue: Decimal
    @State private var notesText: String
    let onSave: (Goal) -> Void
    
    init(goal: Goal, onSave: @escaping (Goal) -> Void) {
        _goal = State(initialValue: goal)
        _targetValue = State(initialValue: goal.targetAmount.value)
        _savedValue = State(initialValue: goal.savedAmount.value)
        _notesText = State(initialValue: goal.notes ?? "")
        self.onSave = onSave
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(goal.name.isEmpty ? "New Goal" : "Edit Goal")
                .font(.title2.bold())
            
            Form {
                TextField("Name", text: $goal.name)
                TextField("Target Amount", value: $targetValue, format: .number)
                TextField("Saved Amount", value: $savedValue, format: .number)
                DatePicker("Target Date", selection: Binding(get: { goal.targetDate ?? Date() }, set: { goal.targetDate = $0 }), displayedComponents: [.date])
                    .disabled(goal.targetDate == nil)
                Toggle("Has Target Date", isOn: Binding(
                    get: { goal.targetDate != nil },
                    set: { enabled in
                        goal.targetDate = enabled ? (goal.targetDate ?? Date()) : nil
                    }
                ))
                TextField("Notes", text: $notesText)
            }
            .formStyle(.grouped)
            
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    let code = store.settings.displayCurrencyCode
                    goal.targetAmount = .init(currencyCode: code, value: targetValue)
                    goal.savedAmount = .init(currencyCode: code, value: savedValue)
                    goal.notes = notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notesText
                    onSave(goal)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(goal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || targetValue <= 0)
            }
        }
        .padding()
        .frame(minWidth: 460)
    }
}

