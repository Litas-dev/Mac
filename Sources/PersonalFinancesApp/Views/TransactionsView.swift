import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct TransactionsListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search: String = ""
    @State private var accountFilterID: UUID? = nil
    @State private var editing: Transaction? = nil
    @State private var showingNew: Bool = false
    @State private var importAlert: ImportAlert? = nil
    
    private var filtered: [Transaction] {
        var items = store.transactions
        if let a = accountFilterID {
            items = items.filter { $0.accountId == a || $0.toAccountId == a }
        }
        if !search.isEmpty {
            items = items.filter {
                ($0.payee?.localizedCaseInsensitiveContains(search) ?? false) ||
                ($0.notes?.localizedCaseInsensitiveContains(search) ?? false) ||
                ($0.customCategoryName?.localizedCaseInsensitiveContains(search) ?? false) ||
                $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(search) })
            }
        }
        return items.sorted(by: { $0.date > $1.date })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transactions")
                    .font(.title2.bold())
                Spacer()
                Menu {
                    Button("All Accounts") { accountFilterID = nil }
                    Divider()
                    ForEach(store.accounts.filter { !$0.archived }.sorted(by: { $0.name < $1.name })) { a in
                        Button(a.name) { accountFilterID = a.id }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(filterTitle())
                        Image(systemName: "chevron.down").font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.15)))
                }
                Button("Import CSV") { chooseCSV() }
                    .buttonStyle(.bordered)
                Button("Add") { showingNew = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .top])
            
            List(selection: $store.selectedTransactionID) {
                ForEach(filtered) { t in
                    Button {
                        store.selectedTransactionID = t.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: t.kind))
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.payee ?? title(for: t))
                                    .font(.headline)
                                Text(subtitle(for: t))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(currency(signedAmount(t), code: t.amount.currencyCode))
                                    .monospacedDigit()
                                Text(shortDate(t.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit") { editing = t }
                        Button(role: .destructive) { store.deleteTransaction(id: t.id) } label: { Text("Delete") }
                    }
                    .tag(t.id)
                }
            }
            .searchable(text: $search)
        }
        .sheet(item: $editing) { t in
            EditTransactionView(transaction: t) { updated in
                store.update(updated)
                editing = nil
            }
        }
        .sheet(isPresented: $showingNew) {
            let defaultAccount = store.accounts.first(where: { !$0.archived })?.id
            let new = Transaction(
                kind: .expense,
                date: Date(),
                amount: .init(currencyCode: store.settings.displayCurrencyCode, value: 0),
                accountId: defaultAccount,
                toAccountId: nil,
                category: .other,
                customCategoryName: nil,
                payee: nil,
                notes: nil,
                tags: [],
                relatedBillId: nil,
                relatedIncomeId: nil
            )
            EditTransactionView(transaction: new) { created in
                store.addTransaction(created)
                showingNew = false
            }
        }
        .alert(item: $importAlert) { a in
            Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
        }
    }
    
    private func chooseCSV() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText, UTType.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            importCSV(from: url)
        }
        #endif
    }
    
    private func importCSV(from url: URL) {
        Task {
            do {
                let data = try Data(contentsOf: url)
                let content = String(decoding: data, as: UTF8.self)
                let rows = await Task.detached { CSVImporter.parse(content: content) }.value
                let code = store.settings.displayCurrencyCode
                let imported = rows.compactMap { row -> Transaction? in
                    guard let date = row.date else { return nil }
                    guard let amount = row.amount else { return nil }
                    let kind: Transaction.Kind = amount < 0 ? .expense : .income
                    let absAmount = amount < 0 ? -amount : amount
                    let accountId = matchAccountId(from: row.account)
                    let payee = row.description
                    return Transaction(
                        kind: kind,
                        date: date,
                        amount: .init(currencyCode: code, value: absAmount),
                        accountId: accountId,
                        toAccountId: nil,
                        category: kind == .expense ? .other : nil,
                        customCategoryName: nil,
                        payee: payee,
                        notes: row.memo,
                        tags: [],
                        relatedBillId: nil,
                        relatedIncomeId: nil
                    )
                }
                if imported.isEmpty {
                    importAlert = ImportAlert(title: "Import Complete", message: "No transactions were imported.")
                    return
                }
                store.transactions.append(contentsOf: imported)
                importAlert = ImportAlert(title: "Import Complete", message: "Imported \(imported.count) transactions.")
            } catch {
                importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
            }
        }
    }
    
    private func matchAccountId(from raw: String?) -> UUID? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return store.accounts.first(where: { !$0.archived })?.id
        }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = store.accounts.first(where: { $0.name.caseInsensitiveCompare(normalized) == .orderedSame }) {
            return exact.id
        }
        if let contains = store.accounts.first(where: { $0.name.localizedCaseInsensitiveContains(normalized) || (exactInstitution($0)?.localizedCaseInsensitiveContains(normalized) ?? false) }) {
            return contains.id
        }
        return store.accounts.first(where: { !$0.archived })?.id
    }
    
    private func exactInstitution(_ a: Account) -> String? { a.institution }
    
    private func filterTitle() -> String {
        if let id = accountFilterID, let a = store.accounts.first(where: { $0.id == id }) {
            return a.name
        }
        return "All Accounts"
    }
    
    private func icon(for kind: Transaction.Kind) -> String {
        switch kind {
        case .expense: return "arrow.up.circle"
        case .income: return "arrow.down.circle"
        case .transfer: return "arrow.left.arrow.right.circle"
        }
    }
    
    private func title(for t: Transaction) -> String {
        switch t.kind {
        case .expense: return "Expense"
        case .income: return "Income"
        case .transfer: return "Transfer"
        }
    }
    
    private func subtitle(for t: Transaction) -> String {
        if let accountId = t.accountId, let a = store.accounts.first(where: { $0.id == accountId }) {
            return a.name
        }
        return ""
    }
    
    private func signedAmount(_ t: Transaction) -> Decimal {
        switch t.kind {
        case .income: return t.amount.value
        case .expense: return -t.amount.value
        case .transfer: return 0
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

struct TransactionsDetailView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: Transaction? = nil
    
    var body: some View {
        if let t = store.selectedTransaction {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.payee ?? title(for: t))
                                .font(.title2.bold())
                            Text(shortDate(t.date))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editing = t }
                            .buttonStyle(.borderedProminent)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Amount").font(.headline)
                        Spacer()
                        Text(currency(signedAmount(t), code: t.amount.currencyCode))
                            .font(.title3.monospacedDigit())
                    }
                    
                    if let a = accountName(for: t.accountId) {
                        HStack {
                            Text("Account").font(.headline)
                            Spacer()
                            Text(a).foregroundStyle(.secondary)
                        }
                    }
                    
                    if t.kind == .transfer, let to = accountName(for: t.toAccountId) {
                        HStack {
                            Text("To").font(.headline)
                            Spacer()
                            Text(to).foregroundStyle(.secondary)
                        }
                    }
                    
                    if let cat = categoryLabel(t), !cat.isEmpty {
                        HStack {
                            Text("Category").font(.headline)
                            Spacer()
                            Text(cat).foregroundStyle(.secondary)
                        }
                    }
                    
                    if let notes = t.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes").font(.headline)
                            Text(notes).foregroundStyle(.secondary)
                        }
                    }
                    
                    if !t.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tags").font(.headline)
                            Text(t.tags.joined(separator: ", ")).foregroundStyle(.secondary)
                        }
                    }
                    
                    if t.relatedBillId == nil && t.relatedIncomeId == nil {
                        if let suggestion = suggestionAction(for: t) {
                            Divider()
                            Text("Suggestions").font(.headline)
                            suggestion
                        }
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        store.deleteTransaction(id: t.id)
                    } label: {
                        Text("Delete Transaction")
                    }
                }
                .padding()
            }
            .sheet(item: $editing) { item in
                EditTransactionView(transaction: item) { updated in
                    store.update(updated)
                    editing = nil
                }
            }
        } else {
            VStack {
                Text("Select a transaction")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func suggestionAction(for t: Transaction) -> AnyView? {
        let cal = Calendar.current
        switch t.kind {
        case .expense:
            let windowStart = cal.date(byAdding: .day, value: -5, to: t.date) ?? t.date
            let windowEnd = cal.date(byAdding: .day, value: 5, to: t.date) ?? t.date
            let candidates = store.bills.filter { b in
                !b.hiddenUntilEdited &&
                cal.startOfDay(for: b.nextDueDate) >= cal.startOfDay(for: windowStart) &&
                cal.startOfDay(for: b.nextDueDate) <= cal.startOfDay(for: windowEnd) &&
                b.amount.value == t.amount.value &&
                !b.isPaidFor(date: b.nextDueDate)
            }
            if let bill = candidates.first {
                return AnyView(
                    Button("Mark \(bill.name) as paid") {
                        store.logPayment(for: bill.id, on: t.date, customAmount: t.amount)
                        var updated = t
                        updated.relatedBillId = bill.id
                        store.update(updated)
                    }
                    .buttonStyle(.borderedProminent)
                )
            }
        case .income:
            let windowStart = cal.date(byAdding: .day, value: -5, to: t.date) ?? t.date
            let windowEnd = cal.date(byAdding: .day, value: 5, to: t.date) ?? t.date
            let candidates = store.incomes.filter { inc in
                cal.startOfDay(for: inc.nextPayDate) >= cal.startOfDay(for: windowStart) &&
                cal.startOfDay(for: inc.nextPayDate) <= cal.startOfDay(for: windowEnd) &&
                inc.amount.value == t.amount.value &&
                !inc.receipts.contains { cal.isDate($0.date, inSameDayAs: inc.nextPayDate) }
            }
            if let inc = candidates.first {
                return AnyView(
                    Button("Log receipt for \(inc.name)") {
                        store.logReceipt(for: inc.id, on: t.date)
                        var updated = t
                        updated.relatedIncomeId = inc.id
                        store.update(updated)
                    }
                    .buttonStyle(.borderedProminent)
                )
            }
        case .transfer:
            break
        }
        return nil
    }
    
    private func accountName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return store.accounts.first(where: { $0.id == id })?.name
    }
    
    private func categoryLabel(_ t: Transaction) -> String? {
        if let custom = t.customCategoryName, !custom.isEmpty { return custom }
        return t.category?.rawValue.capitalized
    }
    
    private func title(for t: Transaction) -> String {
        switch t.kind {
        case .expense: return "Expense"
        case .income: return "Income"
        case .transfer: return "Transfer"
        }
    }
    
    private func signedAmount(_ t: Transaction) -> Decimal {
        switch t.kind {
        case .income: return t.amount.value
        case .expense: return -t.amount.value
        case .transfer: return 0
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

private struct EditTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var transaction: Transaction
    @State private var amountValue: Decimal
    @State private var tagsText: String
    @State private var customCategory: String
    let onSave: (Transaction) -> Void
    
    init(transaction: Transaction, onSave: @escaping (Transaction) -> Void) {
        _transaction = State(initialValue: transaction)
        _amountValue = State(initialValue: transaction.amount.value)
        _tagsText = State(initialValue: transaction.tags.joined(separator: ", "))
        _customCategory = State(initialValue: transaction.customCategoryName ?? "")
        self.onSave = onSave
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(transaction.id == UUID() ? "New Transaction" : "Edit Transaction")
                .font(.title2.bold())
            
            Form {
                Picker("Type", selection: $transaction.kind) {
                    ForEach(Transaction.Kind.allCases, id: \.self) { k in
                        Text(k.rawValue.capitalized).tag(k)
                    }
                }
                DatePicker("Date", selection: $transaction.date, displayedComponents: [.date])
                TextField("Amount", value: $amountValue, format: .number)
                Picker("Account", selection: Binding(get: { transaction.accountId }, set: { transaction.accountId = $0 })) {
                    Text("None").tag(UUID?.none)
                    ForEach(store.accounts.filter { !$0.archived }.sorted(by: { $0.name < $1.name })) { a in
                        Text(a.name).tag(UUID?.some(a.id))
                    }
                }
                if transaction.kind == .transfer {
                    Picker("To Account", selection: Binding(get: { transaction.toAccountId }, set: { transaction.toAccountId = $0 })) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.accounts.filter { !$0.archived }.sorted(by: { $0.name < $1.name })) { a in
                            Text(a.name).tag(UUID?.some(a.id))
                        }
                    }
                }
                if transaction.kind == .expense {
                    Picker("Category", selection: Binding(get: { transaction.category ?? .other }, set: { transaction.category = $0 })) {
                        ForEach(Bill.Category.allCases, id: \.self) { c in
                            Text(c.rawValue.capitalized).tag(c)
                        }
                    }
                    TextField("Custom Category", text: $customCategory)
                }
                TextField("Payee", text: Binding(get: { transaction.payee ?? "" }, set: { transaction.payee = $0.isEmpty ? nil : $0 }))
                TextField("Notes", text: Binding(get: { transaction.notes ?? "" }, set: { transaction.notes = $0.isEmpty ? nil : $0 }))
                TextField("Tags", text: $tagsText)
            }
            .formStyle(.grouped)
            
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    transaction.amount = .init(currencyCode: store.settings.displayCurrencyCode, value: amountValue)
                    transaction.tags = tagsText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    transaction.customCategoryName = customCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : customCategory
                    if transaction.kind != .transfer { transaction.toAccountId = nil }
                    if transaction.kind != .expense { transaction.category = nil; transaction.customCategoryName = nil }
                    onSave(transaction)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(amountValue == 0)
            }
        }
        .padding()
        .frame(minWidth: 460)
    }
}

private struct ImportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum CSVImporter {
    struct Row {
        var date: Date?
        var amount: Decimal?
        var description: String?
        var memo: String?
        var account: String?
    }
    
    static func parse(content: String) -> [Row] {
        let records = parseCSV(content: content)
            .filter { fields in
                fields.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }
        guard let header = records.first else { return [] }
        
        let headerFields = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let map = headerMap(headerFields)
        
        var rows: [Row] = []
        for fields in records.dropFirst() {
            var row = Row()
            row.date = parseDate(field(fields, map.dateIndex))
            row.amount = parseDecimal(field(fields, map.amountIndex))
            row.description = field(fields, map.descriptionIndex)
            row.memo = field(fields, map.memoIndex)
            row.account = field(fields, map.accountIndex)
            rows.append(row)
        }
        return rows
    }
    
    private struct HeaderMap {
        var dateIndex: Int?
        var amountIndex: Int?
        var descriptionIndex: Int?
        var memoIndex: Int?
        var accountIndex: Int?
    }
    
    private static func headerMap(_ headers: [String]) -> HeaderMap {
        func idx(_ names: [String]) -> Int? {
            for n in names {
                if let i = headers.firstIndex(where: { $0 == n }) { return i }
            }
            return nil
        }
        return HeaderMap(
            dateIndex: idx(["date", "posted date", "transaction date"]),
            amountIndex: idx(["amount", "transaction amount", "value"]),
            descriptionIndex: idx(["description", "name", "payee", "merchant"]),
            memoIndex: idx(["memo", "notes", "category"]),
            accountIndex: idx(["account", "account name"])
        )
    }
    
    private static func field(_ fields: [String], _ index: Int?) -> String? {
        guard let index, index >= 0, index < fields.count else { return nil }
        let v = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }
    
    private static func parseDecimal(_ s: String?) -> Decimal? {
        guard var s else { return nil }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        
        var isNegative = false
        if s.hasPrefix("(") && s.hasSuffix(")") {
            isNegative = true
            s = String(s.dropFirst().dropLast())
        }
        s = s.replacingOccurrences(of: "−", with: "-")
        s = s.replacingOccurrences(of: " ", with: "")
        s = s.replacingOccurrences(of: "\u{00A0}", with: "")
        for sym in ["$", "€", "£", "NOK", "SEK", "DKK", "USD", "EUR", "GBP"] {
            s = s.replacingOccurrences(of: sym, with: "", options: [.caseInsensitive])
        }
        
        let lastComma = s.lastIndex(of: ",")
        let lastDot = s.lastIndex(of: ".")
        if let lastComma, let lastDot {
            if lastComma > lastDot {
                s = s.replacingOccurrences(of: ".", with: "")
                s = s.replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if lastComma != nil {
            s = s.replacingOccurrences(of: ",", with: ".")
        }
        
        if s.hasPrefix("+") { s = String(s.dropFirst()) }
        if let d = Decimal(string: s) {
            return isNegative ? -d : d
        }
        return nil
    }
    
    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let d = isoFormatter.date(from: trimmed) { return d }
        
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/").map { String($0) }
            if parts.count == 3, let a = Int(parts[0]), let b = Int(parts[1]) {
                if a > 12 {
                    if let df = dateFormatter(for: "dd/MM/yyyy"), let d = df.date(from: trimmed) { return d }
                }
                if b > 12 {
                    if let df = dateFormatter(for: "MM/dd/yyyy"), let d = df.date(from: trimmed) { return d }
                }
            }
        }
        
        for df in dateFormatters {
            if let d = df.date(from: trimmed) { return d }
        }
        return nil
    }
    
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private static func dateFormatter(for format: String) -> DateFormatter? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = format
        return df
    }
    
    private static var dateFormatters: [DateFormatter] = {
        let formats = ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd", "MM/dd/yyyy", "dd/MM/yyyy", "MMM d, yyyy", "d MMM yyyy"]
        return formats.map { f in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = f
            return df
        }
    }()
    
    private static func parseCSV(content: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        
        var i = content.startIndex
        while i < content.endIndex {
            let ch = content[i]
            if ch == "\"" {
                let next = content.index(after: i)
                if inQuotes, next < content.endIndex, content[next] == "\"" {
                    field.append("\"")
                    i = content.index(after: next)
                    continue
                } else {
                    inQuotes.toggle()
                    i = content.index(after: i)
                    continue
                }
            }
            if ch == ",", !inQuotes {
                row.append(field)
                field = ""
                i = content.index(after: i)
                continue
            }
            if (ch == "\n" || ch == "\r"), !inQuotes {
                row.append(field)
                field = ""
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    rows.append(row)
                }
                row = []
                if ch == "\r" {
                    let next = content.index(after: i)
                    if next < content.endIndex, content[next] == "\n" {
                        i = content.index(after: next)
                        continue
                    }
                }
                i = content.index(after: i)
                continue
            }
            field.append(ch)
            i = content.index(after: i)
        }
        row.append(field)
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            rows.append(row)
        }
        return rows
    }
}
