import Foundation

enum AICommandType: String, Codable {
    case expense
    case send_invoice
    case pay_bill
    case reminder
    case income
    case error
}

struct AIParsedCommand: Codable {
    let type: AICommandType
    let amount: Decimal?
    let category: String?
    let contact: String?
    let bill: String?
    let text: String?
    let date: String?
    let name: String?
    let recurrence: String?
    let dueDay: Int?
    let error: String?
}

final class AICommandParser {
    struct Config {
        enum Provider { case local, externalGroq }
        var endpoint: URL = URL(string: "http://localhost:11434/api/generate")!
        var model: String = "qwen3.5:4b"
        var timeout: TimeInterval = 120
        var provider: Provider = .local
        var apiKey: String? = nil
    }
    private let config: Config
    init(config: Config = .init()) { self.config = config }
    
    static func categoryForName(_ name: String) -> Bill.Category {
        let s = name.lowercased()
        let tokens: Set<String> = Set(
            s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map { String($0) }
        )
        func has(_ kws: [String]) -> Bool {
            for k in kws {
                if s.contains(k) || tokens.contains(k) { return true }
            }
            return false
        }
        if has(["rent","mortgage","apartment","flat","house"]) { return .housing }
        if has(["electricity","power","energy","internet","wifi","broadband","water","gas","mobile","phone","tv","trash"]) { return .utilities }
        if has([
            "netflix","spotify","prime","amazon","youtube","yt","premium","icloud","itunes","apple","notion",
            "vpn","nordvpn","surfshark","expressvpn","magazine","news","kindle","audible","hbo","max","disney",
            "viaplay","canal","paramount","tidal","deezer","office","microsoft","onedrive","google","drive",
            "subscription","subscriptions","abonnement","abonement","abonementas","prenumerata","prenumeracija","game","pass","patreon"
        ]) { return .subscriptions }
        if has(["insurance","insur","policy"]) { return .insurance }
        if has(["tax","vat","property","road","taxes"]) { return .taxes }
        if has(["fuel","diesel","gasoline","transport","bus","train","metro","parking","uber","taxi","toll","car","loan","payment"]) { return .transport }
        return .other
    }
    
    func parse(userInput: String) async throws -> AIParsedCommand {
        let systemPrompt = """
        You are a command parser for a finance app.
        Rules:
        - Return ONLY one JSON object
        - No explanations, no extra text
        - Normalize: dates as "YYYY-MM-DD", numbers as plain numbers
        - If input is unclear, output: { "error": "unknown_command" }
        
        Schemas:
        - expense: { "type":"expense", "amount": number, "category":"string", "date":"YYYY-MM-DD" optional }
        - income: { "type":"income", "amount": number, "name":"string" optional, "date":"YYYY-MM-DD" optional }
        - pay_bill: { "type":"pay_bill", "bill":"string", "amount": number optional, "date":"YYYY-MM-DD" optional, "recurrence":"monthly" optional, "dueDay": number optional }
        - reminder: { "type":"reminder", "text":"string", "date":"YYYY-MM-DD" }
        
        Guidance:
        - If the text has a name before a comma, treat that as the title/name.
        - Understand dates: "today", "tomorrow", "in N days", "on YYYY-MM-DD".
        - Monthly: phrases like "monthly", "every month", "each month"; if day is present set "dueDay", else "dueDay":1.
        - Output keys exactly as in schemas.
        
        Examples:
        Input: spent 250 on groceries
        Output: { "type": "expense", "amount": 250, "category": "groceries" }
        
        Input: website creation, income for 1000 today
        Output: { "type": "income", "amount": 1000, "name": "website creation", "date": "YYYY-MM-DD" }
        
        Input: car fixing, bill to pay 10000 in 10 days
        Output: { "type": "pay_bill", "bill": "car fixing", "amount": 10000, "date": "YYYY-MM-DD" }
        
        Input: rent apartament, 7500 every month 1 dday of the month
        Output: { "type": "pay_bill", "bill": "rent apartament", "amount": 7500, "recurrence": "monthly", "dueDay": 1 }
        
        Input: do something
        Output: { "error": "unknown_command" }
        """
        if config.provider != .local {
            if let cmd = try await tryExternal(systemPrompt: systemPrompt, userInput: userInput) { return cmd }
        } else {
            let candidates: [String] = [config.model, "qwen:3.5-4b", "qwen-3.5:4b", "qwen3.5:4b", "qwen2.5:4b"]
            for modelName in candidates {
                if let cmd = try await tryGenerate(model: modelName, systemPrompt: systemPrompt, userInput: userInput) {
                    return cmd
                }
            }
        }
        if let fallback = heuristicParse(userInput) { return fallback }
        return AIParsedCommand(type: .error, amount: nil, category: nil, contact: nil, bill: nil, text: nil, date: nil, name: nil, recurrence: nil, dueDay: nil, error: "model_unavailable")
    }
    
    private func tryExternal(systemPrompt: String, userInput: String) async throws -> AIParsedCommand? {
        var req = URLRequest(url: config.endpoint)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        // Groq only
        if let k = config.apiKey { req.addValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = [
            "model": "llama-3.1-8b-instant",
            "messages": [
                ["role":"system","content": systemPrompt],
                ["role":"user","content": userInput]
            ],
            "temperature": 0,
            "stream": false
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, _) = try await URLSession.shared.data(for: req, delegate: nil)
        // Try OpenAI-like content -> choices[0].message.content
        if let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let choices = obj["choices"] as? [[String: Any]],
           let msg = choices.first?["message"] as? [String: Any],
           let content = msg["content"] as? String {
            return decodeCommand(from: content)
        }
        // Try "response" field
        struct AnyResp: Decodable { let response: String? }
        if let any = try? JSONDecoder().decode(AnyResp.self, from: data), let text = any.response {
            return decodeCommand(from: text)
        }
        // Fallback: treat body as text
        if let text = String(data: data, encoding: .utf8) {
            return decodeCommand(from: text)
        }
        return nil
    }
    private func decodeCommand(from text: String) -> AIParsedCommand? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIParsedCommand.self, from: jsonData)
    }
    
    private func tryGenerate(model: String, systemPrompt: String, userInput: String) async throws -> AIParsedCommand? {
        let body: [String: Any] = [
            "model": model,
            "system": systemPrompt,
            "prompt": userInput,
            "stream": false,
            "format": "json",
            "keep_alive": "1h"
        ]
        var req = URLRequest(url: config.endpoint)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, _) = try await URLSession.shared.data(for: req, delegate: nil)
        struct OllamaResp: Decodable { let response: String? }
        guard let decoded = try? JSONDecoder().decode(OllamaResp.self, from: data),
              let raw = decoded.response?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let jsonData = raw.data(using: .utf8)
        else { return nil }
        if let cmd = try? JSONDecoder().decode(AIParsedCommand.self, from: jsonData) {
            return cmd
        }
        return nil
    }
    
    private func heuristicParse(_ input: String) -> AIParsedCommand? {
        let t = input.lowercased()
        let number = extractAmount(from: t)
        let due = parseDate(from: t)
        if t.contains("remind") || t.contains("reminder") {
            let date = due != nil ? isoDate(due!) : extractAfter(t, keywords: ["on ", "at ", "tomorrow", "today"])
            let txt = input
            return AIParsedCommand(type: .reminder, amount: nil, category: nil, contact: nil, bill: nil, text: txt, date: date, name: nil, recurrence: nil, dueDay: nil, error: nil)
        }
        if t.contains("send invoice") || t.contains("invoice to") {
            let c = extractAfter(t, keywords: ["to "])
            return AIParsedCommand(type: .send_invoice, amount: nil, category: nil, contact: c.isEmpty ? nil : c, bill: nil, text: nil, date: nil, name: nil, recurrence: nil, dueDay: nil, error: nil)
        }
        if t.contains("spent") || t.contains("spend") || t.contains("expense") || t.contains("bought") || t.contains("buy") {
            let cat = extractAfter(t, keywords: ["on ", "for "])
            return AIParsedCommand(type: .expense, amount: number, category: cat.isEmpty ? "other" : cat, contact: nil, bill: nil, text: nil, date: nil, name: nil, recurrence: nil, dueDay: nil, error: nil)
        }
        if t.contains("income") || t.contains("received") || t.contains("got paid") || t.contains("payment from") {
            let (isMonthlyInc, monthlyDayInc) = parseMonthly(t)
            var title = nameFromCommaPrefix(input) ?? extractAfter(t, keywords: ["from ", "for "])
            if title.isEmpty, let before = nameBeforeKeyword(input, keyword: "income") { title = before }
            return AIParsedCommand(type: .income, amount: number, category: nil, contact: nil, bill: nil, text: nil, date: due != nil ? isoDate(due!) : nil, name: title.isEmpty ? "Income" : title, recurrence: isMonthlyInc ? "monthly" : nil, dueDay: monthlyDayInc, error: nil)
        }
        let (isMonthly, monthlyDay) = parseMonthly(t)
        if (t.contains("pay") || t.contains("bill") || t.contains("rent") || t.contains("invoice")) {
            // Prefer a human-provided title before a comma, e.g., "Car fixing, bill to pay 1000"
            let commaName = nameFromCommaPrefix(input)
            var b = extractAfter(t, keywords: ["for ", "bill ", "pay "])
            if let cn = commaName, !cn.isEmpty { b = cn.lowercased() }
            return AIParsedCommand(
                type: .pay_bill,
                amount: number,
                category: nil,
                contact: nil,
                bill: b.isEmpty ? nil : b,
                text: nil,
                date: due != nil ? isoDate(due!) : nil,
                name: nil,
                recurrence: isMonthly ? "monthly" : nil,
                dueDay: monthlyDay,
                error: nil
            )
        }
        return nil
    }
    
    // Prefer the largest numeric value that is NOT part of "in N days"
    private func extractAmount(from s: String) -> Decimal? {
        let withoutDays = s.replacingOccurrences(of: #"in\s+\d+\s+days?"#, with: "", options: .regularExpression)
        let nums = allNumbers(in: withoutDays)
        return nums.max()
    }
    private func allNumbers(in s: String) -> [Decimal] {
        let pattern = #"([0-9][0-9\ \.,]*)"#
        guard let r = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        let matches = r.matches(in: s, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { m in
            let raw = ns.substring(with: m.range(at: 1))
            let cleaned = raw
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "€", with: "")
                .replacingOccurrences(of: "$", with: "")
            return Decimal(string: cleaned)
        }
    }
    
    private func extractAfter(_ s: String, keywords: [String]) -> String {
        for k in keywords {
            if let r = s.range(of: k) {
                let tail = s[r.upperBound...]
                return String(tail).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }
    
    private func parseDate(from s: String) -> Date? {
        let trimmed = s.lowercased()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        if trimmed.contains("today") { return today }
        if trimmed.contains("tomorrow") { return cal.date(byAdding: .day, value: 1, to: today) }
        if let match = matchRegex(trimmed, pattern: #"in\s+(\d+)\s+days?"#),
           let n = Int(match) {
            return cal.date(byAdding: .day, value: n, to: today)
        }
        // on 2026-03-30
        if let dstr = matchRegex(trimmed, pattern: #"on\s+(\d{4}-\d{2}-\d{2})"#) {
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; return df.date(from: dstr)
        }
        return nil
    }
    private func parseMonthly(_ s: String) -> (Bool, Int?) {
        let t = s.replacingOccurrences(of: "  ", with: " ").lowercased()
        let has = t.contains("monthly") || t.contains("every month") || t.contains("each month")
        if !has { return (false, nil) }
        // try to find a day number near the word "day"
        if let dstr = matchRegex(t, pattern: #"(\d{1,2})\s*(?:st|nd|rd|th)?\s*(?:d?day)?(?:\s*of\s*the\s*month)?"#),
           let d = Int(dstr), d >= 1, d <= 28 { // 28 to be safe
            return (true, d)
        }
        // fallback look for any 1-28 number
        if let any = matchRegex(t, pattern: #"\b([1-2]?\d|28)\b"#), let d = Int(any), d >= 1, d <= 28 {
            return (true, d)
        }
        return (true, 1)
    }
    private func matchRegex(_ s: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
    private func isoDate(_ d: Date) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; return df.string(from: d)
    }
    private func nameFromCommaPrefix(_ input: String) -> String? {
        if let idx = input.firstIndex(of: ",") {
            let prefix = input[..<idx].trimmingCharacters(in: .whitespacesAndNewlines)
            let low = prefix.lowercased()
            if low.isEmpty { return nil }
            // Avoid generic phrases
            if low.contains("bill") || low.contains("pay") || low.contains("amount") || low.contains("in ") { return nil }
            return String(prefix)
        }
        return nil
    }
    private func nameBeforeKeyword(_ input: String, keyword: String) -> String? {
        let low = input.lowercased()
        guard let r = low.range(of: " \(keyword) ") ?? low.range(of: "\(keyword) ") else { return nil }
        let part = input[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        if part.isEmpty { return nil }
        // Avoid pure numbers or currency blobs
        if part.range(of: #"[0-9€$]"#, options: .regularExpression) != nil { return nil }
        return part
    }
}

extension AppStore {
    func validate(command: AIParsedCommand) -> String? {
        switch command.type {
        case .expense:
            guard command.amount != nil, command.category != nil else { return "Missing amount or category" }
            return nil
        case .income:
            guard command.amount != nil else { return "Missing amount" }
            return nil
        case .send_invoice:
            guard command.contact != nil else { return "Missing contact" }
            return nil
        case .pay_bill:
            guard let bill = command.bill, !bill.isEmpty else { return "Missing bill name" }
            // allow either date OR monthly recurrence OR immediate pay
            if command.date == nil && command.recurrence == nil && command.amount == nil {
                // at least a name is fine (will create and pay 0)
            }
            if let rec = command.recurrence, rec != "monthly" {
                return "Unsupported recurrence"
            }
            if command.recurrence == "monthly", (command.dueDay ?? 1) < 1 {
                return "Invalid monthly day"
            }
            return nil
        case .reminder:
            guard command.text != nil, command.date != nil else { return "Missing text or date" }
            return nil
        case .error:
            return "unknown_command"
        }
    }
    
    func execute(command: AIParsedCommand) -> String {
        switch command.type {
        case .income:
            guard let amount = command.amount else { return "Missing amount" }
            let rawName = (command.name ?? "Income")
            let split = Self.splitShortName(from: rawName)
            let name = split.short
            let amt = DecimalAmount(currencyCode: settings.displayCurrencyCode, value: amount)
            let now = Date()
            if let rec = command.recurrence, rec == "monthly" {
                let day = command.dueDay ?? 1
                let next = AppStore.nextMonthlyDate(day: day)
                let inc = Income(name: name, amount: amt, source: .other, customSourceName: name, recurrence: .monthly, nextPayDate: next, notes: split.note ?? "Scheduled via Command Bar", receipts: [])
                addIncome(inc)
                return "Scheduled income \(settings.displayCurrencyCode) \(amount) for \(name) monthly on day \(day)"
            } else if let dstr = command.date, let d = AppStore.parseISO(dstr) {
                if d <= Calendar.current.startOfDay(for: now) {
                    var inc = Income(name: name, amount: amt, source: .other, customSourceName: name, recurrence: .once, nextPayDate: d, notes: split.note ?? "Logged via Command Bar", receipts: [])
                    inc.logReceipt(on: d, amount: amt)
                    addIncome(inc)
                    if let defaultAccountId = accounts.first(where: { !$0.archived })?.id {
                        addTransaction(Transaction(
                            kind: .income,
                            date: d,
                            amount: amt,
                            accountId: defaultAccountId,
                            toAccountId: nil,
                            category: nil,
                            customCategoryName: inc.customSourceName,
                            payee: inc.name,
                            notes: "Logged via Command Bar",
                            tags: [],
                            relatedBillId: nil,
                            relatedIncomeId: inc.id
                        ))
                    }
                    return "Logged income \(settings.displayCurrencyCode) \(amount) for \(name) on \(dstr)"
                } else {
                    let inc = Income(name: name, amount: amt, source: .other, customSourceName: name, recurrence: .once, nextPayDate: d, notes: split.note ?? "Scheduled via Command Bar", receipts: [])
                    addIncome(inc)
                    return "Scheduled income \(settings.displayCurrencyCode) \(amount) for \(name) on \(dstr)"
                }
            } else {
                var inc = Income(name: name, amount: amt, source: .other, customSourceName: name, recurrence: .once, nextPayDate: now, notes: split.note ?? "Logged via Command Bar", receipts: [])
                inc.logReceipt(on: now, amount: amt)
                addIncome(inc)
                if let defaultAccountId = accounts.first(where: { !$0.archived })?.id {
                    addTransaction(Transaction(
                        kind: .income,
                        date: now,
                        amount: amt,
                        accountId: defaultAccountId,
                        toAccountId: nil,
                        category: nil,
                        customCategoryName: inc.customSourceName,
                        payee: inc.name,
                        notes: "Logged via Command Bar",
                        tags: [],
                        relatedBillId: nil,
                        relatedIncomeId: inc.id
                    ))
                }
                return "Logged income \(settings.displayCurrencyCode) \(amount) for \(name)"
            }
        case .expense:
            guard let amount = command.amount, let cat = command.category else { return "Missing amount or category" }
            let amt = DecimalAmount(currencyCode: settings.displayCurrencyCode, value: amount)
            let now = Date()
            if let defaultAccountId = accounts.first(where: { !$0.archived })?.id {
                let mapped = Bill.Category(rawValue: cat.lowercased())
                let t = Transaction(
                    kind: .expense,
                    date: now,
                    amount: amt,
                    accountId: defaultAccountId,
                    toAccountId: nil,
                    category: mapped ?? .other,
                    customCategoryName: mapped == nil ? cat.capitalized : nil,
                    payee: cat.capitalized,
                    notes: "Logged via Command Bar",
                    tags: [],
                    relatedBillId: nil,
                    relatedIncomeId: nil
                )
                addTransaction(t)
                return "Logged expense \(settings.displayCurrencyCode) \(amount) → \(cat.capitalized)"
            } else {
                let name = cat.capitalized
                let bill = Bill(name: name, amount: amt, category: Bill.Category(rawValue: cat.lowercased()) ?? .other, customCategoryName: nil, recurrence: .once, nextDueDate: now, notes: "Created via Command Bar", payments: [], paidAutomatically: false, hiddenUntilEdited: false)
                bills.append(bill)
                if let idx = bills.firstIndex(where: { $0.id == bill.id }) {
                    bills[idx].markPaid(on: now, amount: amt)
                }
                return "Logged expense \(settings.displayCurrencyCode) \(amount) → \(name)"
            }
        case .pay_bill:
            guard let billName = command.bill else { return "Missing bill name" }
            // If a due date is provided, schedule (do not pay now)
            if let dateStr = command.date, let due = Self.parseISO(dateStr) {
                if let idx = bills.firstIndex(where: { $0.name.localizedCaseInsensitiveContains(billName) }) {
                    var b = bills[idx]
                    if let override = command.amount {
                        b.amount = DecimalAmount(currencyCode: settings.displayCurrencyCode, value: override)
                    }
                    b.recurrence = .once
                    b.nextDueDate = due
                    b.notes = billName.capitalized
                    bills[idx] = b
                    return "Scheduled \(b.name) on \(dateStr)"
                } else {
                    let amtVal = command.amount ?? 0
                    let amt = DecimalAmount(currencyCode: settings.displayCurrencyCode, value: amtVal)
                    let split = Self.splitShortName(from: billName)
                    let cat = AICommandParser.categoryForName(split.short)
                    let bill = Bill(name: split.short, amount: amt, category: cat, customCategoryName: nil, recurrence: .once, nextDueDate: due, notes: split.note ?? billName.capitalized, payments: [], paidAutomatically: false, hiddenUntilEdited: false)
                    bills.append(bill)
                    return "Scheduled \(split.short) on \(dateStr)"
                }
            } else if command.recurrence == "monthly" {
                let day = command.dueDay ?? 1
                let due = Self.nextMonthlyDate(day: day)
                if let idx = bills.firstIndex(where: { $0.name.localizedCaseInsensitiveContains(billName) }) {
                    var b = bills[idx]
                    if let override = command.amount {
                        b.amount = DecimalAmount(currencyCode: settings.displayCurrencyCode, value: override)
                    }
                    b.recurrence = .monthly
                    b.nextDueDate = due
                    b.notes = billName.capitalized
                    bills[idx] = b
                    return "Scheduled \(b.name) monthly on day \(day)"
                } else {
                    let amtVal = command.amount ?? 0
                    let amt = DecimalAmount(currencyCode: settings.displayCurrencyCode, value: amtVal)
                    let split = Self.splitShortName(from: billName)
                    let cat = AICommandParser.categoryForName(split.short)
                    let bill = Bill(name: split.short, amount: amt, category: cat, customCategoryName: nil, recurrence: .monthly, nextDueDate: due, notes: split.note ?? billName.capitalized, payments: [], paidAutomatically: false, hiddenUntilEdited: false)
                    bills.append(bill)
                    return "Scheduled \(split.short) monthly on day \(day)"
                }
            }
            if let b = bills.first(where: { $0.name.localizedCaseInsensitiveContains(billName) }) {
                if let override = command.amount {
                    let amt = DecimalAmount(currencyCode: settings.displayCurrencyCode, value: override)
                    logPayment(for: b.id, on: Date(), customAmount: amt)
                    return "Paid \(b.name) \(settings.displayCurrencyCode) \(override)"
                } else {
                    logPayment(for: b.id)
                    return "Paid \(b.name)"
                }
            } else {
                let amtVal = command.amount ?? 0
                let amt = DecimalAmount(currencyCode: settings.displayCurrencyCode, value: amtVal)
                let split = Self.splitShortName(from: billName)
                let cat = AICommandParser.categoryForName(split.short)
                let bill = Bill(name: split.short, amount: amt, category: cat, customCategoryName: nil, recurrence: .once, nextDueDate: Date(), notes: split.note ?? billName.capitalized, payments: [], paidAutomatically: false, hiddenUntilEdited: false)
                bills.append(bill)
                if let idx = bills.firstIndex(where: { $0.id == bill.id }) {
                    bills[idx].markPaid(on: Date(), amount: amt)
                }
                return "Paid \(split.short) \(settings.displayCurrencyCode) \(amtVal)"
            }
        case .send_invoice:
            return "Preview only"
        case .reminder:
            return "Preview only"
        case .error:
            return "Unknown command"
        }
    }
    private static func parseISO(_ s: String) -> Date? {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; return df.date(from: s)
    }
    private static func nextMonthlyDate(day: Int) -> Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month], from: now)
        let clamped = max(1, min(day, 28))
        comps.day = clamped
        let this = cal.date(from: comps) ?? now
        if cal.startOfDay(for: this) >= cal.startOfDay(for: now) {
            return this
        }
        return cal.date(byAdding: .month, value: 1, to: this) ?? this
    }
    private static func splitShortName(from raw: String) -> (short: String, note: String?) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = s
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != " " })
            .joined()
            .split(separator: " ")
            .map { String($0) }
        let stop: Set<String> = ["bill","pay","payment","in","day","days","every","each","month","monthly","week","weekly","to","the","a","an","of","on","for"]
        let words = tokens.filter { !$0.allSatisfy(\.isNumber) && !stop.contains($0) }
        let pick = Array(words.prefix(2))
        let short = pick.map { $0.capitalized }.joined(separator: " ").isEmpty ? s.capitalized : pick.map { $0.capitalized }.joined(separator: " ")
        let noteCandidates = tokens.filter { !pick.contains($0) }
        let note = noteCandidates.isEmpty ? nil : s.capitalized
        return (short, note)
    }
}
