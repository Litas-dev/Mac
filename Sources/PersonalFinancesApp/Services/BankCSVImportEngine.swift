import Foundation

enum BankCSVImportEngine {
    struct Result: Hashable {
        var createdAccounts: Int
        var importedTransactions: Int
        var skippedDuplicates: Int
        var skippedUnassigned: Int
    }
    
    static func apply(plan: BankCSVImporter.ImportPlan, store: AppStore, createAccounts: Bool, adjustSettings: Bool = true) -> Result {
        var result = Result(createdAccounts: 0, importedTransactions: 0, skippedDuplicates: 0, skippedUnassigned: 0)
        store.performBatchUpdate {
            if adjustSettings {
                store.settings.preferManualForecastBalance = true
                store.settings.hideAccountBalances = true
            }
            result = _apply(plan: plan, store: store, createAccounts: createAccounts)
        }
        return result
    }
    
    private static func _apply(plan: BankCSVImporter.ImportPlan, store: AppStore, createAccounts: Bool) -> Result {
        func normalized(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        
        func matchExistingAccountId(name: String, currencyCode: String) -> UUID? {
            let n = normalized(name)
            return store.accounts.first(where: { !$0.archived && normalized($0.name) == n && $0.currencyCode == currencyCode })?.id
        }
        
        var createdAccounts = 0
        var numberToId: [String: UUID] = [:]
        
        if createAccounts {
            for a in plan.detectedAccounts {
                if let existing = matchExistingAccountId(name: a.name, currencyCode: a.currencyCode) {
                    numberToId[a.normalizedNumber] = existing
                    continue
                }
                let created = Account(
                    name: a.name,
                    kind: a.kind,
                    currencyCode: a.currencyCode,
                    openingBalance: 0,
                    institution: nil,
                    notes: "Imported from bank CSV",
                    archived: false
                )
                store.addAccount(created)
                createdAccounts += 1
                numberToId[a.normalizedNumber] = created.id
            }
        } else {
            for a in plan.detectedAccounts {
                if let existing = matchExistingAccountId(name: a.name, currencyCode: a.currencyCode) {
                    numberToId[a.normalizedNumber] = existing
                }
            }
        }
        
        let defaultAccountId = store.accounts.first(where: { !$0.archived })?.id
        
        func txKey(kind: Transaction.Kind, date: Date, amount: DecimalAmount, accountId: UUID?, toAccountId: UUID?, payee: String?, notes: String?) -> String {
            let day = Int(date.timeIntervalSince1970 / 86400)
            let amt = NSDecimalNumber(decimal: amount.value).stringValue
            return [
                "\(day)",
                kind.rawValue,
                amt,
                amount.currencyCode,
                accountId?.uuidString ?? "",
                toAccountId?.uuidString ?? "",
                (payee ?? ""),
                (notes ?? "")
            ].joined(separator: "|")
        }
        
        var existingKeys = Set(store.transactions.map { t in
            txKey(kind: t.kind, date: t.date, amount: t.amount, accountId: t.accountId, toAccountId: t.toAccountId, payee: t.payee, notes: t.notes)
        })
        
        var imported = 0
        var skippedDup = 0
        var skippedUnassigned = 0
        
        for p in plan.transactions {
            let accId = numberToId[p.accountNumber] ?? defaultAccountId
            guard let accId else {
                skippedUnassigned += 1
                continue
            }
            let toId: UUID? = {
                guard p.kind == .transfer, let toNum = p.toInternalAccountNumber else { return nil }
                return numberToId[toNum]
            }()
            
            let amount = DecimalAmount(currencyCode: p.currencyCode, value: p.amount)
            let key = txKey(kind: p.kind, date: p.date, amount: amount, accountId: accId, toAccountId: toId, payee: p.payee, notes: p.notes)
            if existingKeys.contains(key) {
                skippedDup += 1
                continue
            }
            existingKeys.insert(key)
            
            let tx = Transaction(
                kind: p.kind,
                date: p.date,
                amount: amount,
                accountId: accId,
                toAccountId: toId,
                category: p.kind == .expense ? .other : nil,
                customCategoryName: nil,
                payee: p.payee,
                notes: p.notes,
                tags: ["bank-csv"],
                relatedBillId: nil,
                relatedIncomeId: nil
            )
            store.transactions.append(tx)
            imported += 1
        }
        
        return Result(
            createdAccounts: createdAccounts,
            importedTransactions: imported,
            skippedDuplicates: skippedDup,
            skippedUnassigned: skippedUnassigned
        )
    }
}
