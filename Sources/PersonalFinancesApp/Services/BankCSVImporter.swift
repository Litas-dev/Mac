import Foundation

enum BankCSVImporter {
    struct DetectedAccount: Hashable {
        var normalizedNumber: String
        var displayNumber: String
        var name: String
        var kind: Account.Kind
        var currencyCode: String
    }
    
    struct PlannedTransaction: Hashable {
        var date: Date
        var kind: Transaction.Kind
        var amount: Decimal
        var currencyCode: String
        
        var fromAccountNumber: String?
        var toAccountNumber: String?
        
        var accountNumber: String
        var toInternalAccountNumber: String?
        
        var payee: String?
        var notes: String?
    }
    
    struct ImportPlan: Hashable {
        var files: [URL]
        var detectedAccounts: [DetectedAccount]
        var transactions: [PlannedTransaction]
        var warnings: [String]
        var dateMin: Date?
        var dateMax: Date?
    }
    
    static func makePlan(urls: [URL]) throws -> ImportPlan {
        var rows: [ParsedRow] = []
        var warnings: [String] = []
        for url in urls {
            let parsed = try parseFile(url: url)
            rows.append(contentsOf: parsed.rows)
            warnings.append(contentsOf: parsed.warnings)
        }
        
        let internalAccountSet = detectInternalAccountNumbers(rows: rows)
        let detectedAccounts = detectAccounts(rows: rows, internalAccountSet: internalAccountSet)
        let txs = buildTransactions(rows: rows, internalAccountSet: internalAccountSet)
        
        let dates = txs.map(\.date)
        let minDate = dates.min()
        let maxDate = dates.max()
        
        return ImportPlan(
            files: urls,
            detectedAccounts: detectedAccounts,
            transactions: txs,
            warnings: warnings,
            dateMin: minDate,
            dateMax: maxDate
        )
    }
}

private extension BankCSVImporter {
    struct ParsedRow: Hashable {
        var bookedDate: Date
        var description: String
        var type: String
        var subtype: String
        
        var fromNumber: String
        var fromName: String
        
        var toNumber: String
        var toName: String
        
        var amount: Decimal
        var currencyCode: String
        var status: String
        var message: String
    }
    
    struct ParsedFile: Hashable {
        var rows: [ParsedRow]
        var warnings: [String]
    }
    
    struct HeaderIndex: Hashable {
        struct Field: Hashable {
            var idx: Int?
            
            func string(_ cols: [String]) -> String {
                guard let idx, idx >= 0, idx < cols.count else { return "" }
                return cols[idx]
            }
            
            func parseDate(_ cols: [String]) -> Date? {
                let raw = string(cols).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { return nil }
                let df = DateFormatter()
                df.dateFormat = "dd.MM.yyyy"
                df.locale = Locale(identifier: "nb_NO")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                return df.date(from: raw)
            }
        }
        
        var bookedDate: Field
        var description: Field
        var type: Field
        var subtype: Field
        var fromAccount: Field
        var senderName: Field
        var toAccount: Field
        var receiverName: Field
        var amountIn: Field
        var amountOut: Field
        var currency: Field
        var status: Field
        var message: Field
        
        init(headers: [String]) {
            let normalized = headers.map { Self.normalizeHeader($0) }
            
            func pick(_ keys: [String]) -> Field {
                for (i, h) in normalized.enumerated() {
                    for k in keys where h.contains(k) {
                        return Field(idx: i)
                    }
                }
                return Field(idx: nil)
            }
            
            bookedDate = pick(["bokfortdato", "bokfort", "bokfrt", "bokfrtdato", "bookeddate", "posteddate"])
            description = pick(["beskrivelse", "beskriv", "description", "tekst"])
            type = pick(["type"])
            subtype = pick(["undertype", "subtype"])
            fromAccount = pick(["frakonto", "frkonto", "fromaccount", "accountfrom"])
            senderName = pick(["avsender", "avs", "sender"])
            toAccount = pick(["tilkonto", "tilkont", "toaccount", "accountto"])
            receiverName = pick(["mottakernavn", "mottaker", "receiver", "payee"])
            amountIn = pick(["belopinn", "belpinn", "amountin"])
            amountOut = pick(["beloput", "belput", "amountout"])
            currency = pick(["valuta", "currency"])
            status = pick(["status"])
            message = pick(["melding", "kid", "fakt", "memo"])
        }
        
        private static func normalizeHeader(_ s: String) -> String {
            var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
            
            out = out
                .replacingOccurrences(of: "\u{FFFD}", with: "o")
                .replacingOccurrences(of: "ø", with: "o")
                .replacingOccurrences(of: "Ø", with: "o")
                .replacingOccurrences(of: "å", with: "a")
                .replacingOccurrences(of: "Å", with: "a")
                .replacingOccurrences(of: "æ", with: "ae")
                .replacingOccurrences(of: "Æ", with: "ae")
            
            out = out.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "nb_NO"))
            
            out = out
                .replacingOccurrences(of: "/", with: "")
                .replacingOccurrences(of: ".", with: "")
            
            return String(out.filter { $0.isLetter || $0.isNumber }).lowercased()
        }
    }
    
    static func parseFile(url: URL) throws -> ParsedFile {
        let data = try Data(contentsOf: url)
        let content = decode(data: data)
        let delimiter: Character = detectDelimiter(content)
        let table = parseCSV(content: content, delimiter: delimiter)
        guard !table.isEmpty else { return ParsedFile(rows: [], warnings: []) }
        
        let header = table[0]
        let index = HeaderIndex(headers: header)
        
        var warnings: [String] = []
        var parsed: [ParsedRow] = []
        
        for cols in table.dropFirst() {
            if cols.isEmpty { continue }
            
            guard let date = index.bookedDate.parseDate(cols) else { continue }
            let description = index.description.string(cols)
            let type = index.type.string(cols)
            let subtype = index.subtype.string(cols)
            
            let fromNumber = normalizeAccountNumber(index.fromAccount.string(cols))
            let fromDisplay = index.fromAccount.string(cols)
            let fromName = index.senderName.string(cols)
            
            let toNumber = normalizeAccountNumber(index.toAccount.string(cols))
            let toName = index.receiverName.string(cols)
            
            let amount = parseAmount(inValue: index.amountIn.string(cols), outValue: index.amountOut.string(cols))
            let currency = index.currency.string(cols)
            let status = index.status.string(cols)
            let message = index.message.string(cols)
            
            if fromNumber.isEmpty {
                warnings.append("Missing source account number in \(url.lastPathComponent)")
            }
            
            parsed.append(
                ParsedRow(
                    bookedDate: date,
                    description: description,
                    type: type,
                    subtype: subtype,
                    fromNumber: fromNumber.isEmpty ? normalizeAccountNumber(fromDisplay) : fromNumber,
                    fromName: fromName,
                    toNumber: toNumber,
                    toName: toName,
                    amount: amount,
                    currencyCode: currency.isEmpty ? "NOK" : currency,
                    status: status,
                    message: message
                )
            )
        }
        
        return ParsedFile(rows: parsed, warnings: warnings)
    }
    
    static func decode(data: Data) -> String {
        let candidates: [String] = [
            String(data: data, encoding: .utf8),
            String(data: data, encoding: .windowsCP1252),
            String(data: data, encoding: .isoLatin1)
        ]
        .compactMap { $0 }
        
        if candidates.isEmpty {
            return String(decoding: data, as: UTF8.self)
        }
        
        func replacementCount(_ s: String) -> Int {
            s.reduce(0) { $0 + ($1 == "�" ? 1 : 0) }
        }
        
        return candidates.min(by: { replacementCount($0) < replacementCount($1) }) ?? candidates[0]
    }
    
    static func detectDelimiter(_ content: String) -> Character {
        let firstLine = content.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if firstLine.contains(";") { return ";" }
        return ","
    }
    
    static func parseCSV(content: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let delimiterScalar = String(delimiter).unicodeScalars.first!
        
        let scalars = Array(content.unicodeScalars)
        var i = 0
        func flushField() {
            row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
            field = ""
        }
        func flushRow() {
            if row.count == 1, row[0].isEmpty {
                row.removeAll(keepingCapacity: true)
                return
            }
            if !row.isEmpty {
                rows.append(row)
            }
            row.removeAll(keepingCapacity: true)
        }
        
        while i < scalars.count {
            let ch = scalars[i]
            
            if ch == "\"" {
                if inQuotes, i + 1 < scalars.count, scalars[i + 1] == "\"" {
                    field.append("\"")
                    i += 2
                    continue
                } else {
                    inQuotes.toggle()
                    i += 1
                    continue
                }
            }
            
            if !inQuotes, ch == delimiterScalar {
                flushField()
                i += 1
                continue
            }
            
            if !inQuotes, (ch == "\n" || ch == "\r") {
                flushField()
                flushRow()
                if ch == "\r", i + 1 < scalars.count, scalars[i + 1] == "\n" {
                    i += 2
                } else {
                    i += 1
                }
                continue
            }
            
            field.unicodeScalars.append(ch)
            i += 1
        }
        
        if !field.isEmpty || !row.isEmpty {
            flushField()
            flushRow()
        }
        
        return rows
    }
    
    static func normalizeAccountNumber(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let filtered = trimmed.filter { $0.isNumber }
        return filtered
    }
    
    static func parseAmount(inValue: String, outValue: String) -> Decimal {
        let trimmedIn = inValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOut = outValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = parseDecimal(trimmedIn), v != 0 { return v }
        if let v = parseDecimal(trimmedOut), v != 0 { return v }
        return 0
    }
    
    static func parseDecimal(_ raw: String) -> Decimal? {
        let cleaned = raw
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        
        if cleaned.isEmpty { return nil }
        
        if cleaned.contains(",") && !cleaned.contains(".") {
            return Decimal(string: cleaned.replacingOccurrences(of: ",", with: "."))
        }
        return Decimal(string: cleaned)
    }
    
    static func detectInternalAccountNumbers(rows: [ParsedRow]) -> Set<String> {
        var internalSet = Set<String>()
        for r in rows {
            if r.amount < 0 {
                if !r.fromNumber.isEmpty { internalSet.insert(r.fromNumber) }
            } else if r.amount > 0 {
                if !r.toNumber.isEmpty { internalSet.insert(r.toNumber) }
            }
            if isOwnTransfer(row: r) {
                if !r.fromNumber.isEmpty { internalSet.insert(r.fromNumber) }
                if !r.toNumber.isEmpty { internalSet.insert(r.toNumber) }
            }
        }
        return internalSet
    }
    
    static func isOwnTransfer(row: ParsedRow) -> Bool {
        let t = (row.type + " " + row.subtype).lowercased()
        return t.contains("egen") && t.contains("konto")
    }
    
    static func detectAccounts(rows: [ParsedRow], internalAccountSet: Set<String>) -> [DetectedAccount] {
        struct NamePick {
            var number: String
            var displayNumber: String
            var name: String
            var currency: String
        }
        
        var byNumber: [String: NamePick] = [:]
        
        for r in rows {
            if internalAccountSet.contains(r.fromNumber), !r.fromNumber.isEmpty {
                let existing = byNumber[r.fromNumber]
                let chosenName = bestName(existing?.name, r.fromName)
                byNumber[r.fromNumber] = NamePick(
                    number: r.fromNumber,
                    displayNumber: r.fromNumber,
                    name: chosenName,
                    currency: r.currencyCode
                )
            }
            if internalAccountSet.contains(r.toNumber), !r.toNumber.isEmpty {
                let existing = byNumber[r.toNumber]
                let chosenName = bestName(existing?.name, r.toName)
                byNumber[r.toNumber] = NamePick(
                    number: r.toNumber,
                    displayNumber: r.toNumber,
                    name: chosenName,
                    currency: r.currencyCode
                )
            }
        }
        
        return byNumber.values
            .map { pick in
                let name = pick.name.isEmpty ? "Account \(pick.number.suffix(4))" : pick.name
                return DetectedAccount(
                    normalizedNumber: pick.number,
                    displayNumber: pick.displayNumber,
                    name: name,
                    kind: inferKind(from: name),
                    currencyCode: pick.currency.isEmpty ? "NOK" : pick.currency
                )
            }
            .sorted { $0.name < $1.name }
    }
    
    static func inferKind(from name: String) -> Account.Kind {
        let s = name.lowercased()
        if s.contains("spare") { return .savings }
        if s.contains("kred") { return .credit }
        if s.contains("cash") { return .cash }
        return .checking
    }
    
    static func bestName(_ a: String?, _ b: String) -> String {
        let aa = (a ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let bb = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if aa.isEmpty { return bb }
        if bb.isEmpty { return aa }
        if bb.count < aa.count { return bb }
        return aa
    }
    
    static func buildTransactions(rows: [ParsedRow], internalAccountSet: Set<String>) -> [PlannedTransaction] {
        var out: [PlannedTransaction] = []
        out.reserveCapacity(rows.count)
        
        for r in rows {
            let signed = r.amount
            if signed == 0 { continue }
            
            let fromInternal = internalAccountSet.contains(r.fromNumber)
            let toInternal = internalAccountSet.contains(r.toNumber)
            
            let kind: Transaction.Kind
            if fromInternal && toInternal {
                kind = .transfer
            } else if signed < 0 {
                kind = .expense
            } else {
                kind = .income
            }
            
            let absAmount = signed < 0 ? -signed : signed
            
            let accountNumber: String
            let toInternalAccountNumber: String?
            
            if kind == .transfer {
                accountNumber = r.fromNumber
                toInternalAccountNumber = r.toNumber
            } else {
                if fromInternal {
                    accountNumber = r.fromNumber
                } else if toInternal {
                    accountNumber = r.toNumber
                } else {
                    continue
                }
                toInternalAccountNumber = nil
            }
            
            let payee: String? = {
                switch kind {
                case .expense:
                    let candidate = r.toName.isEmpty ? r.description : r.toName
                    return candidate.isEmpty ? nil : candidate
                case .income:
                    let candidate = r.description
                    return candidate.isEmpty ? nil : candidate
                case .transfer:
                    return nil
                }
            }()
            
            let notes = [r.type, r.subtype, r.message]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
            
            out.append(
                PlannedTransaction(
                    date: r.bookedDate,
                    kind: kind,
                    amount: absAmount,
                    currencyCode: r.currencyCode.isEmpty ? "NOK" : r.currencyCode,
                    fromAccountNumber: r.fromNumber.isEmpty ? nil : r.fromNumber,
                    toAccountNumber: r.toNumber.isEmpty ? nil : r.toNumber,
                    accountNumber: accountNumber,
                    toInternalAccountNumber: toInternalAccountNumber,
                    payee: payee,
                    notes: notes.isEmpty ? nil : notes
                )
            )
        }
        
        return out.sorted(by: { $0.date > $1.date })
    }
}
