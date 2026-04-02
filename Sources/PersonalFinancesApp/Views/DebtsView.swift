import SwiftUI

struct DebtsListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search: String = ""
    @State private var editing: Debt? = nil
    @State private var showingNew: Bool = false
    
    private var filtered: [Debt] {
        var items = store.debts.filter { !$0.archived }
        if !search.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(search) || ($0.notes?.localizedCaseInsensitiveContains(search) ?? false) }
        }
        return items.sorted(by: { $0.name < $1.name })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Debts")
                    .font(.title2.bold())
                Spacer()
                Button("Add") { showingNew = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .top])
            
            List(selection: $store.selectedDebtID) {
                ForEach(filtered) { d in
                    Button { store.selectedDebtID = d.id } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: d.kind))
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name).font(.headline)
                                Text(rateText(d))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(currency(d.principal, code: d.currencyCode))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit") { editing = d }
                        Button("Archive") {
                            var updated = d
                            updated.archived = true
                            store.update(updated)
                        }
                    }
                    .tag(d.id)
                }
            }
            .searchable(text: $search)
        }
        .sheet(item: $editing) { d in
            EditDebtView(debt: d) { updated in
                store.update(updated)
                editing = nil
            }
        }
        .sheet(isPresented: $showingNew) {
            let code = store.settings.displayCurrencyCode
            let new = Debt(
                name: "",
                kind: .creditCard,
                currencyCode: code,
                principal: 0,
                annualInterestRate: 0,
                minimumPayment: 0,
                dueDayOfMonth: nil,
                notes: nil,
                archived: false
            )
            EditDebtView(debt: new) { created in
                store.addDebt(created)
                showingNew = false
            }
            #if os(macOS)
            .draggableWindow()
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenAddDebt"))) { _ in
            showingNew = true
        }
    }
    
    private func icon(for kind: Debt.Kind) -> String {
        switch kind {
        case .creditCard: return "creditcard"
        case .loan: return "banknote"
        case .mortgage: return "house"
        case .other: return "percent"
        }
    }
    
    private func rateText(_ d: Debt) -> String {
        let pct = (d.annualInterestRate as NSDecimalNumber).doubleValue
        if pct == 0 { return "No interest set" }
        return String(format: "%.2f%% APR", pct)
    }
    
    private func currency(_ decimal: Decimal, code: String) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = code
        return nf.string(for: decimal as NSDecimalNumber) ?? "\(decimal)"
    }
}

struct DebtsDetailView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: Debt? = nil
    @State private var extraPayment: Decimal = 0
    
    var body: some View {
        if let d = store.selectedDebt {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name).font(.title2.bold())
                            Text(d.kind.rawValue.capitalized)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editing = d }
                            .buttonStyle(.borderedProminent)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Balance").font(.headline)
                        Spacer()
                        Text(currency(d.principal, code: d.currencyCode))
                            .font(.title3.monospacedDigit())
                    }
                    HStack {
                        Text("APR").font(.headline)
                        Spacer()
                        Text(rateText(d)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Minimum").font(.headline)
                        Spacer()
                        Text(currency(d.minimumPayment, code: d.currencyCode)).foregroundStyle(.secondary)
                    }
                    
                    if let due = d.dueDayOfMonth {
                        HStack {
                            Text("Due Day").font(.headline)
                            Spacer()
                            Text("\(due)").foregroundStyle(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    Text("Payoff Projection").font(.headline)
                    HStack(spacing: 10) {
                        TextField("Extra monthly", value: $extraPayment, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                        Spacer()
                    }
                    
                    let projection = payoffProjection(for: d, extraPayment: extraPayment)
                    if let message = projection.message {
                        Text(message).foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text("Months").font(.headline)
                            Spacer()
                            Text("\(projection.months)").monospacedDigit()
                        }
                        HStack {
                            Text("Total Interest").font(.headline)
                            Spacer()
                            Text(currency(projection.totalInterest, code: d.currencyCode)).monospacedDigit()
                        }
                        if let payoffDate = projection.payoffDate {
                            HStack {
                                Text("Payoff Date").font(.headline)
                                Spacer()
                                Text(shortDate(payoffDate)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    if let notes = d.notes, !notes.isEmpty {
                        Divider()
                        Text("Notes").font(.headline)
                        Text(notes).foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        store.deleteDebt(id: d.id)
                    } label: {
                        Text("Delete Debt")
                    }
                }
                .padding()
            }
            .sheet(item: $editing) { item in
                EditDebtView(debt: item) { updated in
                    store.update(updated)
                    editing = nil
                }
            }
        } else {
            VStack {
                Text("Select a debt")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private struct PayoffProjection {
        var months: Int
        var totalInterest: Decimal
        var payoffDate: Date?
        var message: String?
    }
    
    private func payoffProjection(for d: Debt, extraPayment: Decimal) -> PayoffProjection {
        if d.principal <= 0 { return PayoffProjection(months: 0, totalInterest: 0, payoffDate: Date(), message: "Balance is already paid off.") }
        if d.minimumPayment <= 0 { return PayoffProjection(months: 0, totalInterest: 0, payoffDate: nil, message: "Set a minimum payment to compute payoff.") }
        
        let monthlyRate = (d.annualInterestRate / 100) / 12
        let payment = d.minimumPayment + extraPayment
        var balance = d.principal
        var interestTotal: Decimal = 0
        var months = 0
        
        for _ in 0..<600 {
            if balance <= 0 { break }
            let interest = monthlyRate <= 0 ? 0 : (balance * monthlyRate)
            interestTotal += interest
            let newBalance = balance + interest - payment
            months += 1
            if payment <= interest && monthlyRate > 0 {
                return PayoffProjection(months: 0, totalInterest: 0, payoffDate: nil, message: "Payment is too low to reduce the balance.")
            }
            balance = newBalance
        }
        
        if balance > 0 {
            return PayoffProjection(months: months, totalInterest: interestTotal, payoffDate: nil, message: "Payoff exceeds 50 years with these inputs.")
        }
        
        let payoffDate = Calendar.current.date(byAdding: .month, value: months, to: Date())
        return PayoffProjection(months: months, totalInterest: interestTotal, payoffDate: payoffDate, message: nil)
    }
    
    private func rateText(_ d: Debt) -> String {
        let pct = (d.annualInterestRate as NSDecimalNumber).doubleValue
        return String(format: "%.2f%%", pct)
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

private struct EditDebtView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var debt: Debt
    @State private var principalValue: Decimal
    @State private var rateValue: Decimal
    @State private var minPaymentValue: Decimal
    @State private var dueDayText: String
    @State private var notesText: String
    let onSave: (Debt) -> Void
    
    init(debt: Debt, onSave: @escaping (Debt) -> Void) {
        _debt = State(initialValue: debt)
        _principalValue = State(initialValue: debt.principal)
        _rateValue = State(initialValue: debt.annualInterestRate)
        _minPaymentValue = State(initialValue: debt.minimumPayment)
        _dueDayText = State(initialValue: debt.dueDayOfMonth.map(String.init) ?? "")
        _notesText = State(initialValue: debt.notes ?? "")
        self.onSave = onSave
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(debt.name.isEmpty ? "New Debt" : "Edit Debt")
                .font(.title2.bold())
            
            Form {
                TextField("Name", text: $debt.name)
                Picker("Type", selection: $debt.kind) {
                    ForEach(Debt.Kind.allCases, id: \.self) { k in
                        Text(k.rawValue.capitalized).tag(k)
                    }
                }
                TextField("Currency", text: $debt.currencyCode)
                TextField("Balance", value: $principalValue, format: .number)
                TextField("APR (%)", value: $rateValue, format: .number)
                TextField("Minimum Payment", value: $minPaymentValue, format: .number)
                TextField("Due Day (1-28)", text: $dueDayText)
                TextField("Notes", text: $notesText)
            }
            .formStyle(.grouped)
            
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    debt.principal = principalValue
                    debt.annualInterestRate = rateValue
                    debt.minimumPayment = minPaymentValue
                    let day = Int(dueDayText.trimmingCharacters(in: .whitespacesAndNewlines))
                    debt.dueDayOfMonth = (day != nil && day! >= 1 && day! <= 28) ? day : nil
                    debt.notes = notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notesText
                    onSave(debt)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(debt.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || principalValue < 0)
            }
        }
        .padding()
        .frame(minWidth: 460)
    }
}
