import SwiftUI

@main
struct PersonalFinancesApp: App {
    @State private var store = AppStore.makePreview()

    var body: some Scene {
        WindowGroup("Personal Finances") {
            RootSplitView()
                .environmentObject(store)
                .dynamicTypeSize(store.dynamicTypeSize)
                .environment(\.controlSize, store.controlSize)
                .preferredColorScheme(store.settings.preferredColorScheme)
                .tint(store.settings.accentColor.color)
                .onReceive(NotificationCenter.default.publisher(for: .requestStoreReload)) { _ in
                    store = AppStore.makePreview()
                }
        }
        .defaultSize(width: 1100, height: 700)
        WindowGroup("Reports", id: "reports") {
            ReportsView()
                .environmentObject(store)
                .dynamicTypeSize(store.dynamicTypeSize)
                .environment(\.controlSize, store.controlSize)
                .preferredColorScheme(store.settings.preferredColorScheme)
                .tint(store.settings.accentColor.color)
                .onReceive(NotificationCenter.default.publisher(for: .requestStoreReload)) { _ in
                    store = AppStore.makePreview()
                }
        }
    }
}

extension Notification.Name {
    static let requestStoreReload = Notification.Name("pf.requestStoreReload")
}

struct AppSettings: Codable {
    var displayCurrencyCode: String = (Locale.current.currency?.identifier) ?? "USD"
    var enableNotifications: Bool = true
    var reminderDays: Int = 7
    var startOnLogin: Bool = false
    var shareAnonymousData: Bool = true
    var customBillCategories: [String] = []
    var customIncomeCategories: [String] = []
    var budgetCategories: [String] = []
    enum DashboardStyle: String, Codable, CaseIterable {
        case basic
        case advanced
        
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            let raw = (try? c.decode(String.self)) ?? ""
            self = DashboardStyle(rawValue: raw) ?? .advanced
        }
    }
    var dashboardStyle: DashboardStyle = .advanced
    var iCloudEnabled: Bool = true
    var calendarSyncEnabled: Bool = true
    var calendarSyncCalendarName: String = "Bills"
    var calendarSyncMonthsAhead: Int = 3
    var calendarSyncLeadDays: Int = 3
    var aiBaseURL: String = "http://localhost:11434"
    var aiModel: String = "qwen3.5:4b"
    enum AIProvider: String, Codable, CaseIterable {
        case local
        case external
    }
    var aiProvider: AIProvider = .local
    var aiExternalEndpoint: String = "https://api.groq.com/openai/v1/chat/completions"
    enum TextSize: String, Codable, CaseIterable {
        case small, normal, large
    }
    var textSize: TextSize = .normal
    enum Theme: String, Codable, CaseIterable {
        case system, light, dark
    }
    var theme: Theme = .system
    enum AccentColor: String, Codable, CaseIterable {
        case blue, purple, pink, red, orange, yellow, green, mint, teal, cyan, indigo, gray
        
        var color: Color {
            switch self {
            case .blue: return .blue
            case .purple: return .purple
            case .pink: return .pink
            case .red: return .red
            case .orange: return .orange
            case .yellow: return .yellow
            case .green: return .green
            case .mint: return .mint
            case .teal: return .teal
            case .cyan: return .cyan
            case .indigo: return .indigo
            case .gray: return .gray
            }
        }
        
        var label: String { rawValue.capitalized }
    }
    var accentColor: AccentColor = .blue
    // Budgets per category key (builtin:<cat> or custom:<label>). Amount is in display currency units.
    var monthlyBudgets: [String: Decimal] = [:]
    // Current available balance used for forecast (manual input)
    var availableBalance: Decimal = 0
    // AI External API Key (stored in UserDefaults/AppSettings to avoid Keychain prompts)
    var aiExternalAPIKey: String? = nil
}

extension AppSettings {
    var preferredColorScheme: ColorScheme? {
        switch theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    var appearanceKey: String {
        theme.rawValue + "|" + accentColor.rawValue
    }
    
    static func budgetKey(builtin category: Bill.Category) -> String {
        "builtin:" + category.rawValue
    }
    
    static func budgetKey(custom label: String) -> String {
        "custom:" + label
    }
    
    static func budgetDisplayName(for key: String) -> String {
        if key.hasPrefix("builtin:") {
            return String(key.dropFirst("builtin:".count)).capitalized
        }
        if key.hasPrefix("custom:") {
            return String(key.dropFirst("custom:".count))
        }
        return key
    }
    
    func budgetKey(for bill: Bill) -> String {
        if let c = bill.customCategoryName, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.budgetKey(custom: c)
        }
        return Self.budgetKey(builtin: bill.category)
    }
    
    func migratedBudgets() -> AppSettings {
        var updated = self
        var migrated: [String: Decimal] = [:]
        for (k, v) in monthlyBudgets {
            if k.hasPrefix("builtin:") || k.hasPrefix("custom:") {
                migrated[k] = v
                continue
            }
            if Bill.Category(rawValue: k) != nil {
                migrated[Self.budgetKey(builtin: Bill.Category(rawValue: k)!)] = v
                continue
            }
            migrated[Self.budgetKey(custom: k)] = v
        }
        updated.monthlyBudgets = migrated
        return updated
    }
    
    func migratedBudgetCategories() -> AppSettings {
        var updated = self
        if updated.budgetCategories.isEmpty {
            let inferred = updated.monthlyBudgets.keys.compactMap { key -> String? in
                guard key.hasPrefix("custom:") else { return nil }
                let label = String(key.dropFirst("custom:".count))
                return label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : label
            }
            if !inferred.isEmpty {
                updated.budgetCategories = Array(Set(inferred)).sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
            }
        }
        return updated
    }
    
    var generalBillCategories: [String] {
        get { customBillCategories }
        set { customBillCategories = newValue }
    }
    
    var generalIncomeCategories: [String] {
        get { customIncomeCategories }
        set { customIncomeCategories = newValue }
    }
}

final class AppStore: ObservableObject {
    private var suspendPersistence: Bool = false
    @Published var bills: [Bill] {
        didSet {
            if suspendPersistence { return }
            do { try repository.save(bills: bills) } catch { recordPersistenceError(context: "Saving bills", error: error) }
            NotificationManager.shared.scheduleAll(for: bills, settings: settings)
            NotificationManager.shared.updateDockBadge(for: bills, settings: settings)
            CalendarSyncManager.shared.scheduleSync(bills: bills, settings: settings)
        }
    }
    @Published var incomes: [Income] {
        didSet {
            if suspendPersistence { return }
            do { try incomeRepository.save(incomes: incomes) } catch { recordPersistenceError(context: "Saving incomes", error: error) }
        }
    }
    @Published var accounts: [Account] {
        didSet {
            if suspendPersistence { return }
            do { try accountRepository.save(accounts: accounts) } catch { recordPersistenceError(context: "Saving accounts", error: error) }
        }
    }
    @Published var transactions: [Transaction] {
        didSet {
            if suspendPersistence { return }
            do { try transactionRepository.save(transactions: transactions) } catch { recordPersistenceError(context: "Saving transactions", error: error) }
        }
    }
    @Published var goals: [Goal] {
        didSet {
            if suspendPersistence { return }
            do { try goalRepository.save(goals: goals) } catch { recordPersistenceError(context: "Saving goals", error: error) }
        }
    }
    @Published var debts: [Debt] {
        didSet {
            if suspendPersistence { return }
            do { try debtRepository.save(debts: debts) } catch { recordPersistenceError(context: "Saving debts", error: error) }
        }
    }
    @Published var settings: AppSettings {
        didSet {
            if suspendPersistence { return }
            saveSettings()
            StartOnLoginManager.shared.apply(enabled: settings.startOnLogin)
            CalendarSyncManager.shared.scheduleSync(bills: bills, settings: settings)
            objectWillChange.send()
        }
    }
    @Published var lastPersistenceError: String? = nil
    private struct SampleIndex: Codable {
        var billIDs: [UUID] = []
        var incomeIDs: [UUID] = []
        var accountIDs: [UUID] = []
        var transactionIDs: [UUID] = []
        var goalIDs: [UUID] = []
        var debtIDs: [UUID] = []
    }
    private var sampleIndex: SampleIndex
    private var notificationObservers: [NSObjectProtocol] = []
    @Published var selectedBillID: UUID?
    @Published var selectedIncomeID: UUID?
    @Published var selectedAccountID: UUID?
    @Published var selectedTransactionID: UUID?
    @Published var selectedGoalID: UUID?
    @Published var selectedDebtID: UUID?
    @Published var selectedDay: Date? = nil
    @Published var selectedIncomeDay: Date? = nil
    @Published var showCalendarDropdown: Bool = false
    @Published var showOnboardingWizard: Bool = false
    let repository: BillRepository
    let incomeRepository: IncomeRepository
    let accountRepository: AccountRepository
    let transactionRepository: TransactionRepository
    let goalRepository: GoalRepository
    let debtRepository: DebtRepository

    init(
        bills: [Bill],
        repository: BillRepository,
        incomes: [Income],
        incomeRepository: IncomeRepository,
        accounts: [Account],
        accountRepository: AccountRepository,
        transactions: [Transaction],
        transactionRepository: TransactionRepository,
        goals: [Goal],
        goalRepository: GoalRepository,
        debts: [Debt],
        debtRepository: DebtRepository
    ) {
        self.bills = bills
        self.repository = repository
        self.incomes = incomes
        self.incomeRepository = incomeRepository
        self.accounts = accounts
        self.accountRepository = accountRepository
        self.transactions = transactions
        self.transactionRepository = transactionRepository
        self.goals = goals
        self.goalRepository = goalRepository
        self.debts = debts
        self.debtRepository = debtRepository
        self.settings = Self.loadSettings()
        self.sampleIndex = Self.loadSampleIndex()
        StartOnLoginManager.shared.apply(enabled: self.settings.startOnLogin)
        NotificationManager.shared.updateDockBadge(for: bills, settings: settings)
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .notificationLogPayment, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            guard let id = note.userInfo?["billID"] as? UUID else { return }
            self.logPayment(for: id)
        })
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .notificationSkipBill, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            guard let id = note.userInfo?["billID"] as? UUID else { return }
            self.skip(for: id)
        })
    }
    
    deinit {
        for t in notificationObservers {
            NotificationCenter.default.removeObserver(t)
        }
    }

    static func makePreview() -> AppStore {
        let settings = loadSettings()
        let billRepo = FileBillRepository(fileURL: PersistencePaths.fileURL("bills.json", preferICloud: settings.iCloudEnabled))
        let bills = billRepo.loadBills()
        let incomeRepo = FileIncomeRepository(fileURL: PersistencePaths.fileURL("incomes.json", preferICloud: settings.iCloudEnabled))
        let incomes = incomeRepo.loadIncomes()
        let accountRepo = FileAccountRepository(fileURL: PersistencePaths.fileURL("accounts.json", preferICloud: settings.iCloudEnabled))
        let accounts = accountRepo.loadAccounts()
        let transactionRepo = FileTransactionRepository(fileURL: PersistencePaths.fileURL("transactions.json", preferICloud: settings.iCloudEnabled))
        let transactions = transactionRepo.loadTransactions()
        let goalRepo = FileGoalRepository(fileURL: PersistencePaths.fileURL("goals.json", preferICloud: settings.iCloudEnabled))
        let goals = goalRepo.loadGoals()
        let debtRepo = FileDebtRepository(fileURL: PersistencePaths.fileURL("debts.json", preferICloud: settings.iCloudEnabled))
        let debts = debtRepo.loadDebts()
        return AppStore(
            bills: bills,
            repository: billRepo,
            incomes: incomes,
            incomeRepository: incomeRepo,
            accounts: accounts,
            accountRepository: accountRepo,
            transactions: transactions,
            transactionRepository: transactionRepo,
            goals: goals,
            goalRepository: goalRepo,
            debts: debts,
            debtRepository: debtRepo
        )
    }

    func kpis(for month: Date = Date()) -> (income: Decimal, bills: Decimal, net: Decimal) {
        let cal = Calendar.current
        let income: Decimal = incomes.reduce(0) { acc, inc in
            let received = inc.receipts
                .filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
                .reduce(Decimal(0)) { $0 + $1.amount.value }
            let upcoming = cal.isDate(inc.nextPayDate, equalTo: month, toGranularity: .month) &&
            !inc.receipts.contains { Calendar.current.isDate($0.date, inSameDayAs: inc.nextPayDate) }
                ? inc.amount.value : 0
            return acc + received + upcoming
        }
        let paidThisMonth = bills.flatMap { $0.payments }.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }.reduce(Decimal(0)) { $0 + $1.amount.value }
        let unpaidThisMonth = bills.filter {
            cal.isDate($0.nextDueDate, equalTo: month, toGranularity: .month) && !$0.isPaidFor(date: $0.nextDueDate)
        }.reduce(Decimal(0)) { $0 + $1.amount.value }
        let billsTotal: Decimal = paidThisMonth + unpaidThisMonth
        return (income, billsTotal, income - billsTotal)
    }

    var selectedBill: Bill? {
        bills.first(where: { $0.id == selectedBillID })
    }
    var selectedIncome: Income? {
        incomes.first(where: { $0.id == selectedIncomeID })
    }
    var selectedAccount: Account? {
        accounts.first(where: { $0.id == selectedAccountID })
    }
    var selectedTransaction: Transaction? {
        transactions.first(where: { $0.id == selectedTransactionID })
    }
    var selectedGoal: Goal? {
        goals.first(where: { $0.id == selectedGoalID })
    }
    var selectedDebt: Debt? {
        debts.first(where: { $0.id == selectedDebtID })
    }
    
    var dynamicTypeSize: DynamicTypeSize {
        switch settings.textSize {
        case .small: return .small
        case .normal: return .medium
        case .large: return .xxLarge
        }
    }
    var controlSize: ControlSize {
        switch settings.textSize {
        case .small: return .small
        case .normal: return .regular
        case .large: return .large
        }
    }

    func update(_ bill: Bill) {
        if let idx = bills.firstIndex(where: { $0.id == bill.id }) {
            bills[idx] = bill
            selectedBillID = bills[idx].id
        }
    }

    func logPayment(for id: UUID, on date: Date = Date()) {
        guard let idx = bills.firstIndex(where: { $0.id == id }) else { return }
        bills[idx].markPaid(on: date)
        bills[idx].hiddenUntilEdited = true
        selectedBillID = nextDueBillID(excluding: id)
    }
    func logPayment(for id: UUID, on date: Date = Date(), customAmount: DecimalAmount) {
        guard let idx = bills.firstIndex(where: { $0.id == id }) else { return }
        bills[idx].markPaid(on: date, amount: customAmount)
        bills[idx].hiddenUntilEdited = true
        selectedBillID = nextDueBillID(excluding: id)
    }

    func skip(for id: UUID) {
        guard let idx = bills.firstIndex(where: { $0.id == id }) else { return }
        var b = bills[idx]
        b.nextDueDate = b.recurrence.advance(from: b.nextDueDate)
        bills[idx] = b
        selectedBillID = nextDueBillID(excluding: id)
    }
    
    enum SnoozePreset {
        case day1, day3, day7, nextWeek, endOfMonth, custom(Date)
    }
    func snooze(for id: UUID, preset: SnoozePreset) {
        guard let idx = bills.firstIndex(where: { $0.id == id }) else { return }
        var b = bills[idx]
        // Guardrail: soft cap at 3 snoozes
        if b.snoozeCount >= 3 {
            // still allow setting, but could surface a warning in UI
        }
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        let until: Date = {
            switch preset {
            case .day1: return cal.date(byAdding: .day, value: 1, to: base) ?? base
            case .day3: return cal.date(byAdding: .day, value: 3, to: base) ?? base
            case .day7: return cal.date(byAdding: .day, value: 7, to: base) ?? base
            case .nextWeek:
                return cal.date(byAdding: .day, value: 7, to: base) ?? base
            case .endOfMonth:
                var comps = cal.dateComponents([.year, .month], from: base)
                let range = cal.range(of: .day, in: .month, for: base)
                comps.day = (range?.count ?? 28)
                return cal.date(from: comps) ?? base
            case .custom(let d):
                return cal.startOfDay(for: d)
            }
        }()
        b.setSnooze(until: until)
        bills[idx] = b
        // Keep current selection; lists will hide it from urgency views while snoozed
    }
    func clearSnooze(for id: UUID) {
        guard let idx = bills.firstIndex(where: { $0.id == id }) else { return }
        var b = bills[idx]
        b.clearSnooze()
        bills[idx] = b
    }
    
    func processAutoPayments(upTo date: Date = Date()) {
        let cal = Calendar.current
        for i in bills.indices {
            if bills[i].paidAutomatically {
                let due = cal.startOfDay(for: bills[i].nextDueDate)
                let upTo = cal.startOfDay(for: date)
                if due > upTo { continue }
                if bills[i].isPaidFor(date: bills[i].nextDueDate) { continue }
                if bills[i].recurrence == .once {
                    bills[i].markPaid(on: bills[i].nextDueDate)
                    bills[i].hiddenUntilEdited = true
                    continue
                }
                var guardrail = 0
                while cal.startOfDay(for: bills[i].nextDueDate) <= upTo && !bills[i].isPaidFor(date: bills[i].nextDueDate) {
                    let before = bills[i].nextDueDate
                    bills[i].markPaid(on: bills[i].nextDueDate)
                    bills[i].hiddenUntilEdited = true
                    if bills[i].nextDueDate == before { break }
                    guardrail += 1
                    if guardrail > 400 { break }
                }
            }
        }
    }
    
    func addIncome(_ income: Income) {
        incomes.append(income)
        selectedIncomeID = income.id
    }
    func update(_ income: Income) {
        if let idx = incomes.firstIndex(where: { $0.id == income.id }) {
            incomes[idx] = income
            selectedIncomeID = income.id
        }
    }
    func logReceipt(for id: UUID, on date: Date = Date()) {
        guard let idx = incomes.firstIndex(where: { $0.id == id }) else { return }
        incomes[idx].logReceipt(on: date)
        selectedIncomeID = incomes[idx].id
    }
    func skipIncome(for id: UUID) {
        guard let idx = incomes.firstIndex(where: { $0.id == id }) else { return }
        var inc = incomes[idx]
        inc.nextPayDate = inc.recurrence.advance(from: inc.nextPayDate)
        incomes[idx] = inc
        selectedIncomeID = incomes[idx].id
    }
    
    func addAccount(_ account: Account) {
        accounts.append(account)
        selectedAccountID = account.id
    }
    func update(_ account: Account) {
        if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[idx] = account
            selectedAccountID = account.id
        }
    }
    func deleteAccount(id: UUID) {
        accounts.removeAll { $0.id == id }
        if selectedAccountID == id { selectedAccountID = nil }
        if !transactions.isEmpty {
            var updated = transactions
            for i in updated.indices {
                if updated[i].accountId == id { updated[i].accountId = nil }
                if updated[i].toAccountId == id { updated[i].toAccountId = nil }
            }
            transactions = updated
        }
    }
    
    func addTransaction(_ transaction: Transaction) {
        transactions.append(transaction)
        selectedTransactionID = transaction.id
    }
    func update(_ transaction: Transaction) {
        if let idx = transactions.firstIndex(where: { $0.id == transaction.id }) {
            transactions[idx] = transaction
            selectedTransactionID = transaction.id
        }
    }
    func deleteTransaction(id: UUID) {
        transactions.removeAll { $0.id == id }
        if selectedTransactionID == id { selectedTransactionID = nil }
    }
    
    func addGoal(_ goal: Goal) {
        goals.append(goal)
        selectedGoalID = goal.id
    }
    func update(_ goal: Goal) {
        if let idx = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[idx] = goal
            selectedGoalID = goal.id
        }
    }
    func deleteGoal(id: UUID) {
        goals.removeAll { $0.id == id }
        if selectedGoalID == id { selectedGoalID = nil }
    }
    
    func addDebt(_ debt: Debt) {
        debts.append(debt)
        selectedDebtID = debt.id
    }
    func update(_ debt: Debt) {
        if let idx = debts.firstIndex(where: { $0.id == debt.id }) {
            debts[idx] = debt
            selectedDebtID = debt.id
        }
    }
    func deleteDebt(id: UUID) {
        debts.removeAll { $0.id == id }
        if selectedDebtID == id { selectedDebtID = nil }
    }
    
    func balance(forAccountId id: UUID) -> Decimal {
        let opening = accounts.first(where: { $0.id == id })?.openingBalance ?? 0
        var total = opening
        for t in transactions {
            switch t.kind {
            case .income:
                if t.accountId == id { total += t.amount.value }
            case .expense:
                if t.accountId == id { total -= t.amount.value }
            case .transfer:
                if t.accountId == id { total -= t.amount.value }
                if t.toAccountId == id { total += t.amount.value }
            }
        }
        return total
    }
    
    func netWorth(in currencyCode: String? = nil) -> Decimal {
        let relevant = accounts.filter { !$0.archived && (currencyCode == nil || $0.currencyCode == currencyCode) }
        return relevant.reduce(Decimal(0)) { $0 + balance(forAccountId: $1.id) }
    }
    
    var computedAvailableBalance: Decimal {
        let activeAccounts = accounts.filter { !$0.archived }
        if activeAccounts.isEmpty {
            return settings.availableBalance
        }
        let liquid = activeAccounts.filter { $0.kind == .checking || $0.kind == .cash || $0.kind == .savings }
        return liquid.reduce(Decimal(0)) { $0 + balance(forAccountId: $1.id) }
    }
    
    private static func loadSettings() -> AppSettings {
        let key = "AppSettings"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            var migrated = decoded.migratedBudgets().migratedBudgetCategories()
            if migrated.dashboardStyle != decoded.dashboardStyle || migrated.monthlyBudgets != decoded.monthlyBudgets || migrated.budgetCategories != decoded.budgetCategories {
                if let d = try? JSONEncoder().encode(migrated) {
                    UserDefaults.standard.set(d, forKey: key)
                }
            }
            return migrated
        }
        return AppSettings()
    }
    private func saveSettings() {
        let key = "AppSettings"
        do {
            let data = try JSONEncoder().encode(settings)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            recordPersistenceError(context: "Saving settings", error: error)
        }
    }
    
    private func recordPersistenceError(context: String, error: Error) {
        lastPersistenceError = "\(context): \(error.localizedDescription)"
    }
    
    func performBatchUpdate(_ work: () -> Void) {
        suspendPersistence = true
        work()
        suspendPersistence = false
        do { try repository.save(bills: bills) } catch { recordPersistenceError(context: "Saving bills", error: error) }
        do { try incomeRepository.save(incomes: incomes) } catch { recordPersistenceError(context: "Saving incomes", error: error) }
        do { try accountRepository.save(accounts: accounts) } catch { recordPersistenceError(context: "Saving accounts", error: error) }
        do { try transactionRepository.save(transactions: transactions) } catch { recordPersistenceError(context: "Saving transactions", error: error) }
        do { try goalRepository.save(goals: goals) } catch { recordPersistenceError(context: "Saving goals", error: error) }
        do { try debtRepository.save(debts: debts) } catch { recordPersistenceError(context: "Saving debts", error: error) }
        saveSettings()
        StartOnLoginManager.shared.apply(enabled: settings.startOnLogin)
        NotificationManager.shared.scheduleAll(for: bills, settings: settings)
        NotificationManager.shared.updateDockBadge(for: bills, settings: settings)
        objectWillChange.send()
    }
    
    private func nextDueBillID(excluding excluded: UUID?) -> UUID? {
        let candidates = bills.filter { !$0.hiddenUntilEdited && !$0.isSnoozedActive && $0.id != excluded }
        let next = candidates.min(by: { $0.nextDueDate < $1.nextDueDate })
        return next?.id
    }
    private static func loadSampleIndex() -> SampleIndex {
        let key = "SampleIndex"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(SampleIndex.self, from: data) {
            return decoded
        }
        return SampleIndex()
    }
    private func saveSampleIndex() {
        let key = "SampleIndex"
        if let data = try? JSONEncoder().encode(sampleIndex) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    func generateSampleData() {
        let currency = settings.displayCurrencyCode
        let cal = Calendar.current
        let now = Date()
        
        let billNames: [(String, Bill.Category)] = [
            ("Rent", .housing), ("Electricity", .utilities), ("Internet", .utilities),
            ("Mobile", .utilities), ("Gym", .subscriptions), ("Insurance", .insurance),
            ("Netflix", .subscriptions), ("Spotify", .subscriptions), ("Water", .utilities),
            ("Fuel", .transport), ("Groceries", .other), ("Credit Card", .other),
            ("Car Loan", .transport), ("Parking", .transport), ("Cloud Storage", .subscriptions),
            ("Property Tax", .taxes), ("Home Alarm", .utilities), ("Cleaning", .other),
            ("Gaming", .subscriptions), ("VPN", .subscriptions), ("Prime", .subscriptions),
            ("Trash", .utilities), ("Maintenance", .other), ("TV License", .utilities),
            ("Dental Plan", .insurance), ("Life Insurance", .insurance), ("Pet Insurance", .insurance),
            ("Magazines", .subscriptions), ("Kindle", .subscriptions), ("Music Lessons", .other)
        ]
        let recurrences: [Recurrence] = [.monthly, .monthly, .monthly, .weekly, .yearly]
        
        var generatedBills: [Bill] = []
        for (name, cat) in billNames.shuffled() {
            let rec = recurrences.randomElement() ?? .monthly
            let anchorDay = Int.random(in: 1...28)
            var anchor = cal.date(from: .init(year: cal.component(.year, from: now) - 1, month: cal.component(.month, from: now), day: anchorDay)) ?? now
            // Build 12 months (or weeks/yearly equivalents) of payments with some gaps
            var payments: [Payment] = []
            let periods = rec == .weekly ? 52 : (rec == .yearly ? 1 : 12)
            var amountValue = Decimal(Int.random(in: 5...300)) + Decimal(Double.random(in: 0..<1)).rounded(2)
            let amount = DecimalAmount(currencyCode: currency, value: amountValue)
            for _ in 0..<periods {
                let due = anchor
                if Bool.random(probability: 0.8) {
                    let payDate = due
                    payments.append(Payment(date: payDate, amount: amount))
                }
                anchor = rec.advance(from: due)
                if Bool.random(probability: 0.2) {
                    amountValue = (amountValue + Decimal(Int.random(in: -2...3))).clamped(min: 5, max: 9999)
                }
            }
            // Determine next due date after last anchor
            let upcoming = anchor
            let bill = Bill(
                name: name,
                amount: DecimalAmount(currencyCode: currency, value: amountValue),
                category: cat,
                recurrence: rec,
                nextDueDate: upcoming,
                notes: nil,
                payments: payments.sorted(by: { $0.date < $1.date }),
                paidAutomatically: Bool.random(probability: 0.3),
                hiddenUntilEdited: false
            )
            generatedBills.append(bill)
            if generatedBills.count >= 24 { break }
        }
        
        let incomeNames: [(String, Income.Source)] = [
            ("Salary", .salary),
            ("Freelance", .freelance),
            ("Rental", .rental),
            ("Dividends", .investment),
            ("Other", .other)
        ]
        var generatedIncomes: [Income] = []
        for (name, src) in incomeNames {
            var rec: Recurrence
            var base: Decimal
            var receipts: [Payment] = []
            
            let startMonthBack = Int.random(in: 2...11)
            let anchorDay = Int.random(in: 1...28)
            var anchor = cal.date(from: .init(
                year: cal.component(.year, from: now),
                month: cal.component(.month, from: now),
                day: anchorDay)) ?? now
            anchor = cal.date(byAdding: .month, value: -startMonthBack, to: anchor) ?? anchor
            
            switch src {
            case .salary:
                rec = .monthly
                base = Decimal(Int.random(in: 12000...22000))
                for _ in 0..<12 {
                    let factor = 1.0 + Double.random(in: -0.02...0.03)
                    let val = (base * Decimal(factor)).rounded(2)
                    receipts.append(Payment(date: anchor, amount: .init(currencyCode: currency, value: val)))
                    anchor = rec.advance(from: anchor)
                }
            case .rental:
                rec = .monthly
                base = Decimal(Int.random(in: 6000...14000))
                for _ in 0..<12 {
                    if !Bool.random(probability: 0.08) {
                        let factor = 1.0 + Double.random(in: -0.01...0.02)
                        let val = (base * Decimal(factor)).rounded(2)
                        receipts.append(Payment(date: anchor, amount: .init(currencyCode: currency, value: val)))
                    }
                    anchor = rec.advance(from: anchor)
                }
            case .freelance:
                rec = Bool.random() ? .weekly : .monthly
                if rec == .weekly {
                    base = Decimal(Int.random(in: 300...1400))
                    for _ in 0..<52 {
                        if !Bool.random(probability: 0.45) {
                            let factor = 1.0 + Double.random(in: -0.5...0.7)
                            let val = (base * Decimal(factor)).rounded(2).clamped(min: 50, max: 10000)
                            receipts.append(Payment(date: anchor, amount: .init(currencyCode: currency, value: val)))
                        }
                        anchor = rec.advance(from: anchor)
                    }
                } else {
                    base = Decimal(Int.random(in: 3000...9000))
                    for _ in 0..<12 {
                        if !Bool.random(probability: 0.35) {
                            let factor = 1.0 + Double.random(in: -0.4...0.6)
                            let val = (base * Decimal(factor)).rounded(2).clamped(min: 200, max: 20000)
                            receipts.append(Payment(date: anchor, amount: .init(currencyCode: currency, value: val)))
                        }
                        anchor = rec.advance(from: anchor)
                    }
                }
            case .investment:
                rec = .yearly
                base = Decimal(Int.random(in: 500...4000))
                let events = Int.random(in: 1...3)
                for i in 0..<events {
                    let date = cal.date(byAdding: .month, value: i * Int(12/events), to: anchor) ?? anchor
                    let factor = 1.0 + Double.random(in: -0.2...0.8)
                    let val = (base * Decimal(factor)).rounded(2)
                    receipts.append(Payment(date: date, amount: .init(currencyCode: currency, value: val)))
                }
                anchor = cal.date(byAdding: .month, value: Int.random(in: 1...3), to: now) ?? now
            case .other:
                rec = Bool.random() ? .once : .weekly
                base = Decimal(Int.random(in: 100...1200))
                if rec == .weekly {
                    for _ in 0..<40 {
                        if !Bool.random(probability: 0.5) {
                            let factor = 1.0 + Double.random(in: -0.3...0.4)
                            let val = (base * Decimal(factor)).rounded(2).clamped(min: 50, max: 3000)
                            receipts.append(Payment(date: anchor, amount: .init(currencyCode: currency, value: val)))
                        }
                        anchor = rec.advance(from: anchor)
                    }
                } else {
                    for _ in 0..<Int.random(in: 3...6) {
                        let date = cal.date(byAdding: .day, value: Int.random(in: -330...(-10)), to: now) ?? now
                        let factor = 1.0 + Double.random(in: -0.4...0.6)
                        let val = (base * Decimal(factor)).rounded(2)
                        receipts.append(Payment(date: date, amount: .init(currencyCode: currency, value: val)))
                    }
                    anchor = cal.date(byAdding: .day, value: Int.random(in: 0...45), to: now) ?? now
                }
            }
            
            let income = Income(
                name: name,
                amount: DecimalAmount(currencyCode: currency, value: base),
                source: src,
                recurrence: rec,
                nextPayDate: anchor,
                notes: nil,
                receipts: receipts.sorted(by: { $0.date < $1.date })
            )
            generatedIncomes.append(income)
        }
        
        let checking = Account(
            name: "Checking",
            kind: .checking,
            currencyCode: currency,
            openingBalance: Decimal(Int.random(in: 1000...9000)),
            institution: "Sample Bank",
            notes: nil,
            archived: false
        )
        let credit = Account(
            name: "Credit Card",
            kind: .credit,
            currencyCode: currency,
            openingBalance: Decimal(Int.random(in: -2500...(-200))),
            institution: "Sample Bank",
            notes: nil,
            archived: false
        )
        let generatedAccounts: [Account] = [checking, credit]
        
        var generatedTransactions: [Transaction] = []
        for bill in generatedBills {
            for p in bill.payments {
                generatedTransactions.append(Transaction(
                    kind: .expense,
                    date: p.date,
                    amount: p.amount,
                    accountId: checking.id,
                    toAccountId: nil,
                    category: bill.category,
                    customCategoryName: bill.customCategoryName,
                    payee: bill.name,
                    notes: nil,
                    tags: [],
                    relatedBillId: bill.id,
                    relatedIncomeId: nil
                ))
            }
        }
        for inc in generatedIncomes {
            for r in inc.receipts {
                generatedTransactions.append(Transaction(
                    kind: .income,
                    date: r.date,
                    amount: r.amount,
                    accountId: checking.id,
                    toAccountId: nil,
                    category: nil,
                    customCategoryName: inc.customSourceName,
                    payee: inc.name,
                    notes: nil,
                    tags: [],
                    relatedBillId: nil,
                    relatedIncomeId: inc.id
                ))
            }
        }
        
        let generatedGoals: [Goal] = [
            Goal(
                name: "Emergency Fund",
                targetAmount: .init(currencyCode: currency, value: 10000),
                savedAmount: .init(currencyCode: currency, value: 2500),
                targetDate: cal.date(byAdding: .month, value: 10, to: now),
                notes: nil,
                archived: false
            )
        ]
        
        let generatedDebts: [Debt] = [
            Debt(
                name: "Credit Card",
                kind: .creditCard,
                currencyCode: currency,
                principal: 3500,
                annualInterestRate: 19.9,
                minimumPayment: 125,
                dueDayOfMonth: 15,
                notes: nil,
                archived: false
            )
        ]
        
        bills.append(contentsOf: generatedBills)
        incomes.append(contentsOf: generatedIncomes)
        accounts.append(contentsOf: generatedAccounts)
        transactions.append(contentsOf: generatedTransactions.sorted(by: { $0.date < $1.date }))
        goals.append(contentsOf: generatedGoals)
        debts.append(contentsOf: generatedDebts)
        sampleIndex.billIDs.append(contentsOf: generatedBills.map { $0.id })
        sampleIndex.incomeIDs.append(contentsOf: generatedIncomes.map { $0.id })
        sampleIndex.accountIDs.append(contentsOf: generatedAccounts.map { $0.id })
        sampleIndex.transactionIDs.append(contentsOf: generatedTransactions.map { $0.id })
        sampleIndex.goalIDs.append(contentsOf: generatedGoals.map { $0.id })
        sampleIndex.debtIDs.append(contentsOf: generatedDebts.map { $0.id })
        saveSampleIndex()
        NotificationManager.shared.updateDockBadge(for: bills, settings: settings)
    }
    
    func clearSampleData() {
        if !sampleIndex.billIDs.isEmpty {
            bills.removeAll { sampleIndex.billIDs.contains($0.id) }
        }
        if !sampleIndex.incomeIDs.isEmpty {
            incomes.removeAll { sampleIndex.incomeIDs.contains($0.id) }
        }
        if !sampleIndex.accountIDs.isEmpty {
            accounts.removeAll { sampleIndex.accountIDs.contains($0.id) }
        }
        if !sampleIndex.transactionIDs.isEmpty {
            transactions.removeAll { sampleIndex.transactionIDs.contains($0.id) }
        }
        if !sampleIndex.goalIDs.isEmpty {
            goals.removeAll { sampleIndex.goalIDs.contains($0.id) }
        }
        if !sampleIndex.debtIDs.isEmpty {
            debts.removeAll { sampleIndex.debtIDs.contains($0.id) }
        }
        sampleIndex = SampleIndex()
        saveSampleIndex()
        NotificationManager.shared.scheduleAll(for: bills, settings: settings)
        NotificationManager.shared.updateDockBadge(for: bills, settings: settings)
    }
    
    func resetAllData() {
        BillAttachmentStore.shared.deleteAllAttachments()
        bills.removeAll()
        incomes.removeAll()
        accounts.removeAll()
        transactions.removeAll()
        goals.removeAll()
        debts.removeAll()
        selectedBillID = nil
        selectedIncomeID = nil
        selectedAccountID = nil
        selectedTransactionID = nil
        selectedGoalID = nil
        selectedDebtID = nil
        selectedDay = nil
        selectedIncomeDay = nil
        sampleIndex = SampleIndex()
        saveSampleIndex()
        NotificationManager.shared.scheduleAll(for: bills, settings: settings)
        NotificationManager.shared.updateDockBadge(for: bills, settings: settings)
    }
}

private extension Bool {
    static func random(probability p: Double) -> Bool {
        Double.random(in: 0...1) < p
    }
}
private extension Decimal {
    func rounded(_ places: Int) -> Decimal {
        var d = self
        var result = Decimal()
        NSDecimalRound(&result, &d, places, .plain)
        return result
    }
    func clamped(min: Decimal, max: Decimal) -> Decimal {
        if self < min { return min }
        if self > max { return max }
        return self
    }
}
