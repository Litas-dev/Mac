import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    private let currencies = ["USD","EUR","GBP","NOK","SEK","DKK","JPY","CNY","CAD","AUD","CHF","PLN","INR","BRL"]
    private let labelWidth: CGFloat = 180
    private let controlWidth: CGFloat = 320
    @State private var dataAlert: DataAlert? = nil
    @State private var showImportConfirm = false
    @State private var pendingImportURL: URL? = nil
    @State private var newBudgetKey: String = AppSettings.budgetKey(builtin: .housing)
    @State private var newBudgetAmount: String = ""
    
    private enum SettingsSection: String, CaseIterable, Identifiable {
        case general
        case appearance
        case notifications
        case ai
        case data
        case categories
        case budgets
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .general: return "General"
            case .appearance: return "Appearance"
            case .notifications: return "Notifications"
            case .ai: return "AI"
            case .data: return "Data"
            case .categories: return "General Categories"
            case .budgets: return "Budgets"
            }
        }
        
        var systemImage: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "paintpalette"
            case .notifications: return "bell"
            case .ai: return "sparkles"
            case .data: return "externaldrive"
            case .categories: return "tag"
            case .budgets: return "chart.pie"
            }
        }
    }
    
    @AppStorage("settingsSelectedSection") private var settingsSelectedSectionRaw: String = SettingsSection.general.rawValue
    
    private var selectedSection: SettingsSection {
        SettingsSection(rawValue: settingsSelectedSectionRaw) ?? .general
    }
    
    private func select(_ section: SettingsSection) {
        settingsSelectedSectionRaw = section.rawValue
    }

    private var selectedSectionPicker: Binding<SettingsSection> {
        Binding(
            get: { SettingsSection(rawValue: settingsSelectedSectionRaw) ?? .general },
            set: { settingsSelectedSectionRaw = $0.rawValue }
        )
    }
    
    private func ensureBudgetCategoryExists(_ label: String) {
        if !store.settings.budgetCategories.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
            store.settings.budgetCategories.append(label)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.title2.bold())
                .padding(.horizontal)
                .padding(.top, 6)
            
            ViewThatFits(in: .horizontal) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SettingsSection.allCases) { s in
                            Button {
                                select(s)
                            } label: {
                                Label(s.title, systemImage: s.systemImage)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(s == selectedSection ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 2)
                }
                
                HStack(spacing: 10) {
                    Picker("", selection: selectedSectionPicker) {
                        ForEach(SettingsSection.allCases) { s in
                            Label(s.title, systemImage: s.systemImage).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                    .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 2)
            }
            
            Divider().opacity(0.2)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(selectedSection.title)
                        .font(.title3.bold())
                    sectionContent(selectedSection)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
        }
        .id(store.settings.appearanceKey)
        .alert(item: $dataAlert) { a in
            Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
        }
        .alert("Import Data", isPresented: $showImportConfirm) {
            Button("Cancel", role: .cancel) { pendingImportURL = nil }
            Button("Import", role: .destructive) {
                if let url = pendingImportURL {
                    importData(from: url)
                }
                pendingImportURL = nil
            }
        } message: {
            Text("This will replace your current data with the selected file.")
        }
    }
    
    @ViewBuilder
    private func sectionContent(_ section: SettingsSection) -> some View {
        switch section {
        case .general:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Dashboard style").frame(width: labelWidth, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { store.settings.dashboardStyle },
                        set: { store.settings.dashboardStyle = $0 }
                    )) {
                        Text("Basic").tag(AppSettings.DashboardStyle.basic)
                        Text("Advanced").tag(AppSettings.DashboardStyle.advanced)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: controlWidth, alignment: .leading)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Start on login").frame(width: labelWidth, alignment: .leading)
                    Toggle("", isOn: Binding(
                        get: { store.settings.startOnLogin },
                        set: { store.settings.startOnLogin = $0 }
                    ))
                    .labelsHidden()
                    .frame(width: controlWidth, alignment: .leading)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Default currency").frame(width: labelWidth, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { store.settings.displayCurrencyCode },
                        set: { store.settings.displayCurrencyCode = $0 }
                    )) {
                        ForEach(currencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                    .foregroundStyle(.primary)
                    .frame(width: controlWidth, alignment: .leading)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Text size").frame(width: labelWidth, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { store.settings.textSize },
                        set: { store.settings.textSize = $0 }
                    )) {
                        Text("Small").tag(AppSettings.TextSize.small)
                        Text("Normal").tag(AppSettings.TextSize.normal)
                        Text("Large").tag(AppSettings.TextSize.large)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: controlWidth, alignment: .leading)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Setup wizard").frame(width: labelWidth, alignment: .leading)
                    Button("Start Setup Wizard…") {
                        store.showOnboardingWizard = true
                    }
                    .buttonStyle(.bordered)
                    .frame(width: controlWidth, alignment: .leading)
                }
            }
        case .appearance:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Theme").frame(width: labelWidth, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { store.settings.theme },
                        set: { store.settings.theme = $0 }
                    )) {
                        Text("System").tag(AppSettings.Theme.system)
                        Text("Light").tag(AppSettings.Theme.light)
                        Text("Dark").tag(AppSettings.Theme.dark)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: controlWidth, alignment: .leading)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Accent color").frame(width: labelWidth, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { store.settings.accentColor },
                        set: { store.settings.accentColor = $0 }
                    )) {
                        ForEach(AppSettings.AccentColor.allCases, id: \.self) { c in
                            Text(c.label).tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                    .foregroundStyle(.primary)
                    .frame(width: controlWidth, alignment: .leading)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("").frame(width: labelWidth, alignment: .leading)
                    HStack(spacing: 10) {
                        Circle()
                            .fill(store.settings.accentColor.color)
                            .frame(width: 12, height: 12)
                        Text("Applies across the app.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: controlWidth, alignment: .leading)
                }
            }
        case .notifications:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Enable notifications").frame(width: labelWidth, alignment: .leading)
                    Toggle("", isOn: Binding(
                        get: { store.settings.enableNotifications },
                        set: { store.settings.enableNotifications = $0 }
                    ))
                    .labelsHidden()
                    .frame(width: controlWidth, alignment: .leading)
                }
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Remind me").frame(width: labelWidth, alignment: .leading)
                    HStack(spacing: 8) {
                        TextField("", value: Binding(
                            get: { store.settings.reminderDays },
                            set: { store.settings.reminderDays = $0 }
                        ), formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)
                            .disabled(!store.settings.enableNotifications)
                        Text("days before due").foregroundStyle(.secondary)
                    }
                    .frame(width: controlWidth, alignment: .leading)
                }
                Text("You will be notified at 09:00")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, labelWidth)
                
                Divider().opacity(0.2)
                
                HStack(alignment: .firstTextBaseline) {
                    Text("Calendar sync").frame(width: labelWidth, alignment: .leading)
                    Toggle("", isOn: Binding(
                        get: { store.settings.calendarSyncEnabled },
                        set: { newValue in
                            if newValue {
                                Task {
                                    let ok = await CalendarSyncManager.shared.requestAccess()
                                    await MainActor.run {
                                        if ok {
                                            store.settings.calendarSyncEnabled = true
                                        } else {
                                            store.settings.calendarSyncEnabled = false
                                            dataAlert = DataAlert(title: "Calendar Access Denied", message: "Enable Calendar access in System Settings → Privacy & Security → Calendars.")
                                        }
                                    }
                                }
                            } else {
                                store.settings.calendarSyncEnabled = false
                            }
                        }
                    ))
                    .labelsHidden()
                    .frame(width: controlWidth, alignment: .leading)
                }
                
                if store.settings.calendarSyncEnabled {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Calendar name").frame(width: labelWidth, alignment: .leading)
                        TextField("", text: Binding(
                            get: { store.settings.calendarSyncCalendarName },
                            set: { store.settings.calendarSyncCalendarName = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: controlWidth, alignment: .leading)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("Months ahead").frame(width: labelWidth, alignment: .leading)
                        Stepper(
                            "",
                            value: Binding(
                                get: { store.settings.calendarSyncMonthsAhead },
                                set: { store.settings.calendarSyncMonthsAhead = $0 }
                            ),
                            in: 0...12
                        )
                        .labelsHidden()
                        .frame(width: controlWidth, alignment: .leading)
                        Text("\(store.settings.calendarSyncMonthsAhead)")
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("Alert").frame(width: labelWidth, alignment: .leading)
                        Stepper(
                            "",
                            value: Binding(
                                get: { store.settings.calendarSyncLeadDays },
                                set: { store.settings.calendarSyncLeadDays = $0 }
                            ),
                            in: 0...30
                        )
                        .labelsHidden()
                        .frame(width: controlWidth, alignment: .leading)
                        Text(store.settings.calendarSyncLeadDays == 0 ? "No alert" : "\(store.settings.calendarSyncLeadDays) days before")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(alignment: .firstTextBaseline) {
                        Text("").frame(width: labelWidth, alignment: .leading)
                        HStack(spacing: 10) {
                            Button("Manage Calendar Access…") {
                                #if os(macOS)
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                                    NSWorkspace.shared.open(url)
                                }
                                #endif
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Remove Synced Events…") {
                                Task {
                                    let ok = await CalendarSyncManager.shared.removeAllSyncedEvents(bills: store.bills, settings: store.settings)
                                    await MainActor.run {
                                        if ok {
                                            dataAlert = DataAlert(title: "Calendar Cleared", message: "Synced bill events were removed from Calendar.")
                                        } else {
                                            dataAlert = DataAlert(title: "Could Not Remove Events", message: "Calendar access is required to remove synced events.")
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(width: controlWidth, alignment: .leading)
                    }
                    
                    Text("Calendar sync mirrors upcoming due dates. You can always edit everything later in the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, labelWidth)
                }
                
                Button("Refresh Dock Badge") {
                    NotificationManager.shared.updateDockBadge(for: store.bills, settings: store.settings)
                }
                .buttonStyle(.bordered)
                .padding(.leading, labelWidth)
            }
        case .ai:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Provider").frame(width: labelWidth, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { store.settings.aiProvider },
                        set: { store.settings.aiProvider = $0 }
                    )) {
                        Text("Local").tag(AppSettings.AIProvider.local)
                        Text("External").tag(AppSettings.AIProvider.external)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: controlWidth, alignment: .leading)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Model").frame(width: labelWidth, alignment: .leading)
                    TextField("", text: Binding(
                        get: { store.settings.aiModel },
                        set: { store.settings.aiModel = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: controlWidth, alignment: .leading)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(store.settings.aiProvider == .local ? "Base URL" : "Groq Endpoint").frame(width: labelWidth, alignment: .leading)
                    TextField("", text: Binding(
                        get: { store.settings.aiProvider == .local ? store.settings.aiBaseURL : store.settings.aiExternalEndpoint },
                        set: {
                            if store.settings.aiProvider == .local { store.settings.aiBaseURL = $0 }
                            else { store.settings.aiExternalEndpoint = $0 }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: controlWidth, alignment: .leading)
                }
                if store.settings.aiProvider == .external {
                    HStack {
                        Text("Groq API Key").frame(width: labelWidth, alignment: .leading)
                        SecureField("Enter API Key", text: Binding(
                            get: { store.settings.aiExternalAPIKey ?? "" },
                            set: { store.settings.aiExternalAPIKey = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: controlWidth, alignment: .leading)
                    }
                }
                AIParserTestRow(timeout: 60)
                    .frame(width: controlWidth + labelWidth)
            }
        case .data:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("iCloud sync").frame(width: labelWidth, alignment: .leading)
                    Toggle("", isOn: Binding(
                        get: { store.settings.iCloudEnabled },
                        set: { newValue in
                            if newValue {
                                if !PersistencePaths.isICloudAvailable() {
                                    store.settings.iCloudEnabled = false
                                    dataAlert = DataAlert(title: "iCloud Not Available", message: "Sign in to iCloud and enable iCloud Drive to use cloud sync.")
                                    return
                                }
                                if let cloudBase = PersistencePaths.iCloudBaseDirectory() {
                                    do {
                                        try PersistenceMigration.migrateAll(from: PersistencePaths.localBaseDirectory(), to: cloudBase)
                                        store.settings.iCloudEnabled = true
                                        NotificationCenter.default.post(name: .requestStoreReload, object: nil)
                                    } catch {
                                        store.settings.iCloudEnabled = false
                                        dataAlert = DataAlert(title: "Could Not Enable iCloud", message: "Could not migrate data to iCloud.")
                                    }
                                } else {
                                    store.settings.iCloudEnabled = false
                                    dataAlert = DataAlert(title: "iCloud Not Available", message: "iCloud container could not be opened.")
                                }
                            } else {
                                do {
                                    try PersistenceMigration.migrateAll(from: PersistencePaths.baseDirectory(preferICloud: true), to: PersistencePaths.localBaseDirectory())
                                } catch {
                                }
                                store.settings.iCloudEnabled = false
                                NotificationCenter.default.post(name: .requestStoreReload, object: nil)
                            }
                        }
                    ))
                    .labelsHidden()
                    .frame(width: controlWidth, alignment: .leading)
                }
                Text("When enabled, data is saved in iCloud Drive and shared across your Macs signed into the same Apple ID.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, labelWidth)
                
                HStack(alignment: .firstTextBaseline) {
                    Text("Delete iCloud data").frame(width: labelWidth, alignment: .leading)
                    Button("Delete…") {
                        Task {
                            do {
                                try PersistenceMigration.deleteICloudData()
                                await MainActor.run {
                                    dataAlert = DataAlert(title: "iCloud Data Deleted", message: "All cloud data files were removed.")
                                }
                            } catch {
                                await MainActor.run {
                                    dataAlert = DataAlert(title: "Could Not Delete iCloud Data", message: "iCloud data could not be removed.")
                                }
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(width: controlWidth, alignment: .leading)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Export data").frame(width: labelWidth, alignment: .leading)
                    Button("Export…") { exportData() }
                        .buttonStyle(.bordered)
                        .frame(width: controlWidth, alignment: .leading)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Import data").frame(width: labelWidth, alignment: .leading)
                    Button("Import…") { chooseImportFile() }
                        .buttonStyle(.bordered)
                        .frame(width: controlWidth, alignment: .leading)
                }
                Text("Your data is stored locally on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, labelWidth)
            }
        case .categories:
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("General bill categories").font(.headline)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Bill.Category.allCases, id: \.self) { c in
                                Text("• \(c.rawValue.capitalized)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("Built-in categories cannot be deleted.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Divider().opacity(0.2)
                        Text("Custom bill categories").font(.headline)
                        CategoryListEditor(
                            items: Binding(
                                get: { store.settings.generalBillCategories },
                                set: { store.settings.generalBillCategories = $0 }
                            ),
                            usageCount: { label in
                                store.bills.filter { $0.customCategoryName?.caseInsensitiveCompare(label) == .orderedSame }.count
                            },
                            onReassign: { label in
                                var updated = store.bills
                                for i in updated.indices {
                                    if updated[i].customCategoryName?.caseInsensitiveCompare(label) == .orderedSame {
                                        updated[i].customCategoryName = nil
                                        updated[i].category = .other
                                    }
                                }
                                store.bills = updated
                            },
                            onDelete: { label in
                            },
                            addPlaceholder: "Add bill category"
                        )
                        .frame(width: controlWidth, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("General income categories").font(.headline)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Income.Source.allCases, id: \.self) { s in
                                Text("• \(s.rawValue.capitalized)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("Built-in categories cannot be deleted.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Divider().opacity(0.2)
                        Text("Custom income categories").font(.headline)
                        CategoryListEditor(
                            items: Binding(
                                get: { store.settings.generalIncomeCategories },
                                set: { store.settings.generalIncomeCategories = $0 }
                            ),
                            usageCount: { label in
                                store.incomes.filter { $0.customSourceName?.caseInsensitiveCompare(label) == .orderedSame }.count
                            },
                            onReassign: { label in
                                var updated = store.incomes
                                for i in updated.indices {
                                    if updated[i].customSourceName?.caseInsensitiveCompare(label) == .orderedSame {
                                        updated[i].customSourceName = nil
                                        updated[i].source = .other
                                    }
                                }
                                store.incomes = updated
                            },
                            addPlaceholder: "Add income category"
                        )
                        .frame(width: controlWidth, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .budgets:
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Available Balance").font(.headline)
                        HStack(alignment: .firstTextBaseline) {
                            Text("Forecast balance").frame(width: labelWidth, alignment: .leading)
                            TextField("0", text: Binding(
                                get: { NSDecimalNumber(decimal: store.settings.availableBalance).stringValue },
                                set: { if let d = Decimal(string: $0) { store.settings.availableBalance = d } }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140, alignment: .leading)
                            Text(store.settings.displayCurrencyCode).foregroundStyle(.secondary)
                        }
                        Text("Used for the cash flow forecast when you don’t use Accounts.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Budget categories").font(.headline)
                        
                        let builtinKeys = Bill.Category.allCases.map { AppSettings.budgetKey(builtin: $0) }
                        let customKeys = store.settings.budgetCategories.map { AppSettings.budgetKey(custom: $0) }
                        let extraCustomKeys = store.settings.monthlyBudgets.keys
                            .filter { $0.hasPrefix("custom:") && !customKeys.contains($0) }
                        let allKeys = builtinKeys + customKeys + extraCustomKeys
                        let existing = store.settings.monthlyBudgets
                            .filter { $0.value > 0 }
                            .sorted(by: { AppSettings.budgetDisplayName(for: $0.key).localizedCaseInsensitiveCompare(AppSettings.budgetDisplayName(for: $1.key)) == .orderedAscending })
                        
                        CategoryListEditor(
                            items: Binding(
                                get: { store.settings.budgetCategories },
                                set: { store.settings.budgetCategories = $0 }
                            ),
                            usageCount: { label in
                                store.settings.monthlyBudgets[AppSettings.budgetKey(custom: label)] == nil ? 0 : 1
                            },
                            onReassign: { label in
                                store.settings.monthlyBudgets.removeValue(forKey: AppSettings.budgetKey(custom: label))
                            },
                            onDelete: { label in
                                store.settings.monthlyBudgets.removeValue(forKey: AppSettings.budgetKey(custom: label))
                            },
                            addPlaceholder: "Add budget category"
                        )
                        .frame(width: controlWidth, alignment: .leading)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Picker("", selection: Binding(
                                get: { newBudgetKey },
                                set: { newBudgetKey = $0 }
                            )) {
                                ForEach(allKeys, id: \.self) { k in
                                    Text(AppSettings.budgetDisplayName(for: k)).tag(k)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.primary)
                            .foregroundStyle(.primary)
                            .frame(width: 220, alignment: .leading)
                            
                            TextField("Budget", text: $newBudgetAmount)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140, alignment: .leading)
                            
                            Text(store.settings.displayCurrencyCode).foregroundStyle(.secondary)
                            
                            Button("Add") {
                                let trimmed = newBudgetAmount.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard let d = Decimal(string: trimmed), d > 0 else { return }
                                if newBudgetKey.hasPrefix("custom:") {
                                    let label = AppSettings.budgetDisplayName(for: newBudgetKey)
                                    ensureBudgetCategoryExists(label)
                                }
                                store.settings.monthlyBudgets[newBudgetKey] = d
                                newBudgetAmount = ""
                            }
                            .buttonStyle(.bordered)
                            .disabled(Decimal(string: newBudgetAmount.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                        }
                        
                        if existing.isEmpty {
                            Text("No budgets yet. Add one above.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(existing, id: \.key) { entry in
                                let key = entry.key
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Picker("", selection: Binding(
                                        get: { key },
                                        set: { newKey in
                                            if newKey == key { return }
                                            if let v = store.settings.monthlyBudgets[key] {
                                                store.settings.monthlyBudgets.removeValue(forKey: key)
                                                store.settings.monthlyBudgets[newKey] = v
                                            }
                                        }
                                    )) {
                                        ForEach(allKeys, id: \.self) { k in
                                            Text(AppSettings.budgetDisplayName(for: k)).tag(k)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.primary)
                                    .foregroundStyle(.primary)
                                    .frame(width: 220, alignment: .leading)
                                    
                                    TextField("Budget", text: Binding(
                                        get: {
                                            if let v = store.settings.monthlyBudgets[key] {
                                                return NSDecimalNumber(decimal: v).stringValue
                                            }
                                            return ""
                                        },
                                        set: {
                                            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if trimmed.isEmpty {
                                                store.settings.monthlyBudgets.removeValue(forKey: key)
                                                return
                                            }
                                            if let d = Decimal(string: trimmed), d > 0 {
                                                store.settings.monthlyBudgets[key] = d
                                            }
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140, alignment: .leading)
                                    
                                    Text(store.settings.displayCurrencyCode).foregroundStyle(.secondary)
                                    
                                    Button(role: .destructive) {
                                        store.settings.monthlyBudgets.removeValue(forKey: key)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        Text("Budgets track your paid bills in the current month.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func exportData() {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "pfbackup") ?? UTType.data]
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd_HH-mm"
        panel.nameFieldStringValue = "PersonalFinances_Backup_\(df.string(from: Date())).pfbackup"
        if panel.runModal() == .OK, let url = panel.url {
            let backup = DataBackupV2(
                version: 2,
                exportedAt: Date(),
                settings: store.settings,
                bills: store.bills,
                incomes: store.incomes,
                accounts: store.accounts,
                transactions: store.transactions,
                goals: store.goals,
                debts: store.debts
            )
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: url.path) {
                    try fm.removeItem(at: url)
                }
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
                
                let data = try enc.encode(backup)
                let jsonURL = url.appendingPathComponent("backup.json", isDirectory: false)
                try data.write(to: jsonURL, options: .atomic)
                
                let bundleAttachmentsRoot = url.appendingPathComponent("Attachments", isDirectory: true)
                try fm.createDirectory(at: bundleAttachmentsRoot, withIntermediateDirectories: true)
                
                let root = try BillAttachmentStore.shared.attachmentsRootURL()
                let attachmentPaths = Set(store.bills.flatMap { $0.attachments }.map { $0.storedRelativePath })
                for rel in attachmentPaths {
                    let src = root.appendingPathComponent(rel, isDirectory: false)
                    if fm.fileExists(atPath: src.path) {
                        let dest = bundleAttachmentsRoot.appendingPathComponent(rel, isDirectory: false)
                        let parent = dest.deletingLastPathComponent()
                        if !fm.fileExists(atPath: parent.path) {
                            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                        }
                        if fm.fileExists(atPath: dest.path) {
                            try fm.removeItem(at: dest)
                        }
                        try fm.copyItem(at: src, to: dest)
                    }
                }
                
                dataAlert = DataAlert(title: "Export Complete", message: "Saved to \(url.lastPathComponent)")
            } catch {
                dataAlert = DataAlert(title: "Export Failed", message: error.localizedDescription)
            }
        }
        #endif
    }

    private func chooseImportFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json, UTType(filenameExtension: "pfbackup") ?? UTType.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            pendingImportURL = url
            showImportConfirm = true
        }
        #endif
    }

    private func importData(from url: URL) {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        do {
            let data: Data
            let attachmentsSourceURL: URL?
            if url.pathExtension.lowercased() == "pfbackup" {
                let jsonURL = url.appendingPathComponent("backup.json", isDirectory: false)
                data = try Data(contentsOf: jsonURL)
                attachmentsSourceURL = url.appendingPathComponent("Attachments", isDirectory: true)
            } else {
                data = try Data(contentsOf: url)
                attachmentsSourceURL = nil
            }
            let header = try dec.decode(DataBackupHeader.self, from: data)
            switch header.version {
            case 1:
                let backup = try dec.decode(DataBackupV1.self, from: data)
                if let attachmentsSourceURL {
                    restoreAttachments(from: attachmentsSourceURL)
                }
                store.performBatchUpdate {
                    store.settings = backup.settings
                    store.bills = backup.bills
                    store.incomes = backup.incomes
                    store.accounts = []
                    store.transactions = []
                    store.goals = []
                    store.debts = []
                    store.selectedBillID = nil
                    store.selectedIncomeID = nil
                    store.selectedAccountID = nil
                    store.selectedTransactionID = nil
                    store.selectedGoalID = nil
                    store.selectedDebtID = nil
                    store.selectedDay = nil
                    store.selectedIncomeDay = nil
                }
            case 2:
                let backup = try dec.decode(DataBackupV2.self, from: data)
                if let attachmentsSourceURL {
                    restoreAttachments(from: attachmentsSourceURL)
                }
                store.performBatchUpdate {
                    store.settings = backup.settings
                    store.bills = backup.bills
                    store.incomes = backup.incomes
                    store.accounts = backup.accounts
                    store.transactions = backup.transactions
                    store.goals = backup.goals
                    store.debts = backup.debts
                    store.selectedBillID = nil
                    store.selectedIncomeID = nil
                    store.selectedAccountID = nil
                    store.selectedTransactionID = nil
                    store.selectedGoalID = nil
                    store.selectedDebtID = nil
                    store.selectedDay = nil
                    store.selectedIncomeDay = nil
                }
            default:
                dataAlert = DataAlert(title: "Import Failed", message: "Unsupported backup version.")
                return
            }
            dataAlert = DataAlert(title: "Import Complete", message: "Data loaded successfully.")
        } catch {
            dataAlert = DataAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }
    
    private func restoreAttachments(from sourceRoot: URL) {
        let fm = FileManager.default
        BillAttachmentStore.shared.deleteAllAttachments()
        guard let destRoot = try? BillAttachmentStore.shared.attachmentsRootURL() else { return }
        guard let enumerator = fm.enumerator(at: sourceRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        for case let fileURL as URL in enumerator {
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { continue }
            let rel = fileURL.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
            let dest = destRoot.appendingPathComponent(rel, isDirectory: false)
            let parent = dest.deletingLastPathComponent()
            if !fm.fileExists(atPath: parent.path) {
                try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            if fm.fileExists(atPath: dest.path) {
                try? fm.removeItem(at: dest)
            }
            try? fm.copyItem(at: fileURL, to: dest)
        }
    }
}

private struct DataBackupHeader: Codable {
    let version: Int
}

private struct DataBackupV1: Codable {
    let version: Int
    let exportedAt: Date
    let settings: AppSettings
    let bills: [Bill]
    let incomes: [Income]
}

private struct DataBackupV2: Codable {
    let version: Int
    let exportedAt: Date
    let settings: AppSettings
    let bills: [Bill]
    let incomes: [Income]
    let accounts: [Account]
    let transactions: [Transaction]
    let goals: [Goal]
    let debts: [Debt]
}

private struct DataAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
private struct AIParserTestRow: View {
    @EnvironmentObject private var store: AppStore
    @State private var result: String = ""
    @State private var isTesting = false
    var timeout: TimeInterval = 60
    var body: some View {
        HStack {
            Button("Test Parser") { Task { await runTest() } }
                .buttonStyle(.bordered)
            if isTesting { ProgressView().controlSize(.small) }
            Text(result).font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
    }
    private func runTest() async {
        isTesting = true
        result = "Parsing..."
        let provider: AICommandParser.Config.Provider
        let url: URL
        switch store.settings.aiProvider {
        case .local:
            let base = store.settings.aiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            url = URL(string: base + "/api/generate") ?? URL(string: "http://localhost:11434/api/generate")!
            provider = .local
        case .external:
            url = URL(string: store.settings.aiExternalEndpoint) ?? URL(string: "https://api.groq.com/openai/v1/chat/completions")!
            provider = .externalGroq
        }
        let cfg = AICommandParser.Config(endpoint: url, model: store.settings.aiModel, timeout: timeout, provider: provider, apiKey: store.settings.aiExternalAPIKey)
        let parser = AICommandParser(config: cfg)
        do {
            let cmd = try await parser.parse(userInput: "spent 100 on food")
            result = "OK: \(cmd.type.rawValue)"
        } catch {
            result = "Error contacting model"
        }
        isTesting = false
    }
}
// Small reusable editor for category lists
private struct CategoryListEditor: View {
    @Binding var items: [String]
    var usageCount: (String) -> Int
    var onReassign: (String) -> Void
    var onDelete: ((String) -> Void)? = nil
    var addPlaceholder: String = "Add category"
    @State private var newLabel: String = ""
    @State private var pendingDelete: String? = nil
    @State private var showConfirm: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(addPlaceholder, text: $newLabel, onCommit: add)
                    .textFieldStyle(.roundedBorder)
                Button("Add") { add() }.disabled(newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            // List existing
            if items.isEmpty {
                Text("No custom categories yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }), id: \.self) { label in
                    HStack(spacing: 10) {
                        Text(label).font(.body)
                        Spacer()
                        let count = usageCount(label)
                        if count > 0 {
                            Text("\(count)")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Button(role: .destructive) {
                            pendingDelete = label
                            showConfirm = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .help("Delete")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .alert("Delete category?", isPresented: $showConfirm, presenting: pendingDelete) { label in
            let count = usageCount(label)
            if count > 0 {
                Button("Delete and move \(count) items to Other", role: .destructive) {
                    items.removeAll { $0.caseInsensitiveCompare(label) == .orderedSame }
                    onReassign(label)
                    onDelete?(label)
                }
            } else {
                Button("Delete", role: .destructive) {
                    items.removeAll { $0.caseInsensitiveCompare(label) == .orderedSame }
                    onDelete?(label)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { label in
            let count = usageCount(label)
            Text(count > 0 ? "This category is used by \(count) item(s). Deleting will move them to Other." : "This category will be removed.")
        }
    }
    private func add() {
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let capped = trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        if !items.contains(where: { $0.caseInsensitiveCompare(capped) == .orderedSame }) {
            items.append(capped)
        }
        newLabel = ""
    }
}
