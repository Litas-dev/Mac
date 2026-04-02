import SwiftUI

struct AccountsListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search: String = ""
    @State private var editing: Account? = nil
    @State private var showingNew: Bool = false
    @State private var pendingDelete: Account? = nil
    
    private var filtered: [Account] {
        var items = store.accounts.filter { !$0.archived }
        if !search.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(search) || ($0.institution?.localizedCaseInsensitiveContains(search) ?? false) }
        }
        return items.sorted { $0.name < $1.name }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Accounts")
                    .font(.title2.bold())
                Spacer()
                Button("Add") { showingNew = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .top])
            
            List(selection: $store.selectedAccountID) {
                ForEach(filtered) { a in
                    Button {
                        store.selectedAccountID = a.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: a.kind))
                                .font(.title3)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name).font(.headline)
                                Text(a.kind.rawValue.capitalized + (a.institution.map { " • \($0)" } ?? ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.settings.preferManualForecastBalance {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(currency(store.balance(forAccountId: a.id), code: a.currencyCode))
                                    .monospacedDigit()
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit") { editing = a }
                        Button("Archive") {
                            var updated = a
                            updated.archived = true
                            store.update(updated)
                        }
                        Button(role: .destructive) {
                            pendingDelete = a
                        } label: {
                            Text("Delete…")
                        }
                    }
                    .tag(a.id)
                }
            }
            .searchable(text: $search)
        }
        .alert("Delete account?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { a in
            Button("Archive Instead") {
                var updated = a
                updated.archived = true
                store.update(updated)
                pendingDelete = nil
            }
            Button("Delete Account", role: .destructive) {
                store.deleteAccount(id: a.id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { a in
            let count = store.transactions.filter { $0.accountId == a.id || $0.toAccountId == a.id }.count
            Text(count > 0
                 ? "This account is referenced by \(count) transaction(s). Deleting will remove the account and those transactions will become unassigned."
                 : "This will permanently delete the account.")
        }
        .sheet(item: $editing) { a in
            EditAccountView(account: a) { updated in
                store.update(updated)
                editing = nil
            }
        }
        .sheet(isPresented: $showingNew) {
            EditAccountView(account: Account(name: "", kind: .checking, currencyCode: store.settings.displayCurrencyCode)) { created in
                store.addAccount(created)
                showingNew = false
            }
            #if os(macOS)
            .draggableWindow()
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenAddAccount"))) { _ in
            showingNew = true
        }
    }
    
    private func icon(for kind: Account.Kind) -> String {
        switch kind {
        case .checking: return "banknote"
        case .savings: return "tray.and.arrow.down"
        case .credit: return "creditcard"
        case .cash: return "wallet.pass"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .other: return "square.grid.2x2"
        }
    }
    
    private func currency(_ decimal: Decimal, code: String) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = code
        return nf.string(for: decimal as NSDecimalNumber) ?? "\(decimal)"
    }
}

struct AccountsDetailView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: Account? = nil
    @State private var showDeleteConfirm: Bool = false
    
    var body: some View {
        if let a = store.selectedAccount {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name)
                                .font(.title2.bold())
                            Text(a.kind.rawValue.capitalized)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editing = a }
                            .buttonStyle(.borderedProminent)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Balance").font(.headline)
                        Spacer()
                        if store.settings.preferManualForecastBalance {
                            Text("—")
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            Text(currency(store.balance(forAccountId: a.id), code: a.currencyCode))
                                .font(.title3.monospacedDigit())
                        }
                    }
                    
                    if let institution = a.institution, !institution.isEmpty {
                        HStack {
                            Text("Institution").font(.headline)
                            Spacer()
                            Text(institution).foregroundStyle(.secondary)
                        }
                    }
                    if let notes = a.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes").font(.headline)
                            Text(notes).foregroundStyle(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    let recent = store.transactions
                        .filter { $0.accountId == a.id || $0.toAccountId == a.id }
                        .sorted(by: { $0.date > $1.date })
                        .prefix(10)
                    if store.settings.preferManualForecastBalance {
                        Text("Balances are hidden because manual forecast balance is enabled.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if recent.isEmpty {
                        Text("No transactions yet.").foregroundStyle(.secondary)
                    } else {
                        Text("Recent").font(.headline)
                        VStack(spacing: 8) {
                            ForEach(Array(recent), id: \.id) { t in
                                HStack {
                                    Text(shortDate(t.date)).foregroundStyle(.secondary)
                                    Text(t.payee ?? title(for: t)).lineLimit(1)
                                    Spacer()
                                    Text(currency(signedAmount(t, for: a.id), code: a.currencyCode))
                                        .monospacedDigit()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Text("Delete Account")
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                }
                .padding()
            }
            .alert("Delete account?", isPresented: $showDeleteConfirm) {
                Button("Archive Instead") {
                    var updated = a
                    updated.archived = true
                    store.update(updated)
                }
                Button("Delete Account", role: .destructive) {
                    store.deleteAccount(id: a.id)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                let count = store.transactions.filter { $0.accountId == a.id || $0.toAccountId == a.id }.count
                Text(count > 0
                     ? "This account is referenced by \(count) transaction(s). Deleting will remove the account and those transactions will become unassigned."
                     : "This will permanently delete the account.")
            }
            .sheet(item: $editing) { item in
                EditAccountView(account: item) { updated in
                    store.update(updated)
                    editing = nil
                }
            }
        } else {
            VStack {
                Text("Select an account")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func signedAmount(_ t: Transaction, for accountId: UUID) -> Decimal {
        switch t.kind {
        case .income:
            return t.accountId == accountId ? t.amount.value : 0
        case .expense:
            return t.accountId == accountId ? -t.amount.value : 0
        case .transfer:
            if t.accountId == accountId { return -t.amount.value }
            if t.toAccountId == accountId { return t.amount.value }
            return 0
        }
    }
    
    private func title(for t: Transaction) -> String {
        switch t.kind {
        case .income: return "Income"
        case .expense: return "Expense"
        case .transfer: return "Transfer"
        }
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

private struct EditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var account: Account
    let onSave: (Account) -> Void
    
    init(account: Account, onSave: @escaping (Account) -> Void) {
        _account = State(initialValue: account)
        self.onSave = onSave
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(account.name.isEmpty ? "New Account" : "Edit Account")
                .font(.title2.bold())
            
            Form {
                TextField("Name", text: $account.name)
                Picker("Type", selection: $account.kind) {
                    ForEach(Account.Kind.allCases, id: \.self) { k in
                        Text(k.rawValue.capitalized).tag(k)
                    }
                }
                TextField("Currency", text: $account.currencyCode)
                TextField("Opening Balance", value: $account.openingBalance, format: .number)
                TextField("Institution", text: Binding(get: { account.institution ?? "" }, set: { account.institution = $0.isEmpty ? nil : $0 }))
                TextField("Notes", text: Binding(get: { account.notes ?? "" }, set: { account.notes = $0.isEmpty ? nil : $0 }))
            }
            .formStyle(.grouped)
            
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(account)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 420)
    }
}
