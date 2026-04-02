import SwiftUI
#if os(macOS)
import UniformTypeIdentifiers
#endif
#if os(macOS)
import AppKit
#endif

struct RootSplitView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @State private var selectedSection: SidebarSection? = .overview
    @State private var lastNonReportSection: SidebarSection = .overview
    @State private var showCalendarDropdown: Bool = false
    @State private var detailScreen: DetailScreen = .info
    @State private var editingBill: Bill?
    @State private var editingIncome: Income?
    @State private var showIncomeCalendarDropdown: Bool = false
    @State private var showingAdd: Bool = false
    @State private var showPlaceholderAlert: Bool = false
    @State private var placeholderTitle: String = ""
    @State private var showResetAlert: Bool = false
    @State private var aiResetToken: UUID = UUID()
    @State private var touchBarActionBill: Bill?
    @AppStorage("overviewDisplayMode") private var overviewDisplayMode: Int = 0
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    private enum DetailScreen { case info, history, stats }
    
    #if os(macOS)
    private var touchBarBezelColor: NSColor {
        guard let b = store.nextDueUnpaidBill else { return .systemGreen }
        let cal = Calendar.current
        if cal.startOfDay(for: b.nextDueDate) <= cal.startOfDay(for: Date()) { return .systemRed }
        return .systemGreen
    }
    #endif
    
    private var shouldShowOnboarding: Bool {
        if didCompleteOnboarding { return false }
        let hasBills = !store.bills.isEmpty
        let hasIncome = !store.incomes.isEmpty
        let hasAccounts = store.accounts.contains(where: { !$0.archived })
        return !(hasBills || hasIncome || hasAccounts)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selected: $selectedSection)
        } content: {
            if selectedSection == .settings {
                SettingsView()
            } else if selectedSection == .income {
                IncomeListView()
            } else if selectedSection == .accounts {
                AccountsListView()
            } else if selectedSection == .transactions {
                HistoryListView()
            } else if selectedSection == .goals {
                GoalsListView()
            } else if selectedSection == .debts {
                DebtsListView()
            } else if selectedSection == .paidRecently {
                HistoryListView()
            } else if selectedSection == .overview {
                DashboardView()
            } else if selectedSection == .monthlySummary {
                HistoryListView()
            } else if selectedSection == .deferred {
                BillsListView(section: selectedSection ?? .overview, onEdit: { bill in
                    editingBill = bill
                })
            } else {
                BillsListView(section: selectedSection ?? .overview, onEdit: { bill in
                    editingBill = bill
                })
            }
        } detail: {
            if selectedSection == .settings {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Spacer(minLength: 28)
                        Text("Privacy")
                            .font(.headline)
                        Divider()
                        Text("We collect anonymous device information (CPU type and macOS version) to improve compatibility and performance.")
                            .foregroundStyle(.secondary)
                        Text("No personal data is collected.")
                            .font(.footnote)
                            .foregroundStyle(.secondary.opacity(0.8))
                            .padding(.top, 2)
                        Toggle("Share anonymous device data", isOn: Binding(
                            get: { store.settings.shareAnonymousData },
                            set: { store.settings.shareAnonymousData = $0 }
                        ))
                        .toggleStyle(.switch)
                        .padding(.top, 6)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            } else
            if selectedSection == .accounts {
                AccountsDetailView()
            } else
            if selectedSection == .goals {
                GoalsDetailView()
            } else
            if selectedSection == .debts {
                DebtsDetailView()
            } else
            if (selectedSection == .income || selectedSection == .monthlySummary), let income = store.selectedIncome {
                VStack(spacing: 0) {
                    if showIncomeCalendarDropdown {
                        IncomeCalendarView(showHideControl: true, isVisible: true, onToggle: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showIncomeCalendarDropdown.toggle()
                            }
                        })
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        Divider()
                    } else {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showIncomeCalendarDropdown = true
                                }
                            } label: {
                                Image(systemName: "eye")
                                    .font(.title3.weight(.bold))
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Next Payment")
                                            .font(.title2.bold())
                                        Text(fullDate(income.nextPayDate))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(currency(amount: income.amount))
                                        .font(.title3.monospacedDigit())
                                }
                                let isOnce = (income.recurrence == .once)
                                let received = income.receipts.contains { Calendar.current.isDate($0.date, inSameDayAs: income.nextPayDate) }
                                HStack(spacing: 12) {
                                    if !received {
                                        Button("Log Receipt") { store.logReceipt(for: income.id) }
                                    }
                                    if !isOnce {
                                        Button("Handle Later") { store.skipIncome(for: income.id) }
                                    }
                                    Button("Edit") { editingIncome = income }
                                }
                                .buttonStyle(.borderedProminent)
                                do {
                                    let cal = Calendar.current
                                    let d = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: income.nextPayDate)).day ?? 0
                                    if !received && d <= 0 {
                                        GroupBox {
                                            HStack(alignment: .center, spacing: 12) {
                                                Image(systemName: "envelope.badge")
                                                    .foregroundStyle(d == 0 ? .orange : .purple)
                                                    .font(.title2.weight(.bold))
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(d == 0 ? "Expected today" : "Awaiting receipt")
                                                        .font(.headline)
                                                    Text("Confirm when this one‑time income is received.")
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                            }
                                            .padding(.vertical, 6)
                                        }
                                    }
                                }
                                if let notes = income.notes, !notes.isEmpty {
                                    GroupBox {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Notes").font(.headline)
                                            Text(notes).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .padding()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.trailing)
            } else if selectedSection == .paidRecently, let income = store.selectedIncome {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        let date = store.selectedIncomeDay ?? income.nextPayDate
                        VStack(alignment: .leading, spacing: 6) {
                            Text(income.name).font(.title2.bold())
                            Text("Income • \(income.source.rawValue.capitalized)").foregroundStyle(.secondary)
                        }
                        HStack {
                            Text(fullDate(date)).foregroundStyle(.secondary)
                            Spacer()
                            Text(currency(amount: income.amount)).font(Typography.amountFont(for: store.settings))
                                .foregroundStyle(.green)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Type: Income").font(.subheadline).foregroundStyle(.secondary)
                            Text("Category: \(income.source.rawValue.capitalized)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let notes = income.notes, !notes.isEmpty {
                            Divider()
                            GroupBox {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Notes").font(.headline)
                                    Text(notes).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        Divider()
                        HStack(spacing: 12) {
                            Button("Edit") { editingIncome = income }
                            Button(role: .destructive) { 
                                store.incomes.removeAll { $0.id == income.id }
                                store.selectedIncomeID = nil
                            } label: { Text("Delete") }
                        }
                    }
                    .padding()
                }
                .padding(.trailing)
            } else if selectedSection == .income {
                IncomeCalendarView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if (selectedSection == .overview || selectedSection == .dueSoon || selectedSection == .dueThisMonth || selectedSection == .paidRecently || selectedSection == .deferred || selectedSection == .monthlySummary), let bill = store.selectedBill {
                VStack(spacing: 0) {
                    if selectedSection == .overview {
                        if showCalendarDropdown {
                            CalendarOverviewView(showHideControl: true, isVisible: true, onToggle: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showCalendarDropdown.toggle()
                                }
                            })
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            Divider()
                        } else {
                            HStack {
                                Spacer()
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        showCalendarDropdown = true
                                    }
                                } label: {
                                    Image(systemName: "eye")
                                        .font(.title3.weight(.bold))
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 8)
                            }
                            ScrollView { billDetailContent(bill) }
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
            } else if selectedSection == .paidRecently {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                let date = store.selectedDay ?? bill.payments.max(by: { $0.date < $1.date })?.date ?? bill.nextDueDate
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(bill.name).font(.title2.bold())
                                    Text("Bill • \(bill.category.rawValue.capitalized)").foregroundStyle(.secondary)
                                }
                                HStack {
                                    Text(fullDate(date)).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(currency(amount: bill.amount)).font(Typography.amountFont(for: store.settings))
                                }
                                Text("Status: Paid").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Type: Bill").font(.subheadline).foregroundStyle(.secondary)
                                    Text("Category: \(bill.category.rawValue.capitalized)").font(.subheadline).foregroundStyle(.secondary)
                                }
                                if let notes = bill.notes, !notes.isEmpty {
                                    Divider()
                                    GroupBox {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Notes").font(.headline)
                                            Text(notes).foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                Divider()
                                HStack(spacing: 12) {
                                    Button("Edit") { editingBill = bill }
                                    Button(role: .destructive) {
                                        store.bills.removeAll { $0.id == bill.id }
                                        store.selectedBillID = nil
                                    } label: { Text("Delete") }
                                }
                            }
                            .padding()
                        }
                    } else {
                        ScrollView { billDetailContent(bill) }
                    }
                }
                .padding(.trailing)
            } else if selectedSection == .overview {
                CalendarOverviewView(showHideControl: true, isVisible: true, onToggle: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showCalendarDropdown = false
                    }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if selectedSection == .deferred {
                ContentUnavailableView("Deferred bills", systemImage: "pause.circle", description: Text("These are bills you chose to handle later. They will return automatically based on your postpone time."))
            } else {
                ContentUnavailableView("Select a transaction", systemImage: "list.bullet.rectangle.portrait", description: Text("Choose a bill or income to view its details"))
            }
        }
        .onChange(of: selectedSection) { newValue in
            if newValue == .reports {
                openWindow(id: "reports")
                selectedSection = lastNonReportSection
                return
            } else if let s = newValue {
                lastNonReportSection = s
            }
            store.selectedBillID = nil
            editingBill = nil
            showCalendarDropdown = false
            store.selectedDay = nil
            store.selectedIncomeID = nil
            showIncomeCalendarDropdown = false
            store.selectedIncomeDay = nil
            detailScreen = .info
        }
        .onChange(of: store.selectedBill) { _ in
            // When a bill is selected from the list, always show its details (hide calendar drop-down)
            showCalendarDropdown = false
            detailScreen = .info
        }
        .onChange(of: store.selectedIncome) { _ in
            showIncomeCalendarDropdown = false
        }
        #if os(macOS)
        .background(
            TouchBarHost(
                title: store.nextDueUnpaidBill?.name ?? "You are on track this month",
                isEnabled: store.nextDueUnpaidBill != nil,
                bezelColor: touchBarBezelColor,
                titleColor: .white,
                onTap: {
                    guard let b = store.nextDueUnpaidBill else { return }
                    selectedSection = .overview
                    store.selectedBillID = b.id
                    detailScreen = .info
                    touchBarActionBill = b
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0.001)
        )
        #endif
        .onAppear {
            if selectedSection == .overview {
                store.selectedBillID = nil
                showCalendarDropdown = false
                store.selectedDay = nil
                detailScreen = .info
            }
            #if os(macOS)
            for window in NSApplication.shared.windows {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.title = ""
            }
            NotificationManager.shared.updateDockBadge(for: store.bills, settings: store.settings)
            #endif
            store.processAutoPayments()
            Task {
                if store.settings.calendarSyncEnabled {
                    _ = await CalendarSyncManager.shared.requestAccess()
                }
            }
            NotificationManager.shared.requestAuthorization { granted in
                if granted {
                    NotificationManager.shared.scheduleAll(for: store.bills, settings: store.settings)
                }
            }
            if shouldShowOnboarding {
                store.showOnboardingWizard = true
            }
        }
        .popover(item: $editingBill) { b in
            EditBillView(bill: b) { updated in
                store.update(updated)
            }
        }
        .popover(item: $editingIncome) { i in
            EditIncomeView(income: i) { updated in
                store.update(updated)
            }
        }
        .onChange(of: editingBill) { _, newValue in
            if newValue != nil { aiResetToken = UUID() }
        }
        .onChange(of: editingIncome) { _, newValue in
            if newValue != nil { aiResetToken = UUID() }
        }
        .onChange(of: showingAdd) { _, newValue in
            aiResetToken = UUID()
        }
        .popover(isPresented: $showingAdd) {
            if selectedSection == .income {
                NewIncomeView { income in
                    store.addIncome(income)
                    store.selectedIncomeDay = nil
                }
            } else {
                NewBillView { bill in
                    store.bills.append(bill)
                    store.selectedBillID = bill.id
                    store.selectedDay = nil
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu {
                    Button("Add Bill…") {
                        selectedSection = .overview
                        showingAdd = true
                    }
                    Button("Add Income…") {
                        selectedSection = .income
                        showingAdd = true
                    }
                    Divider()
                    Button("Add Sample Data…") {
                        store.generateSampleData()
                    }
                    Button("Clear Sample Data…") {
                        store.clearSampleData()
                    }
                    Divider()
                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        Text("Reset All Data…")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigation) {
                AICommandBarView(resetToken: aiResetToken)
                    .frame(width: 380)
            }
        }
        .alert(placeholderTitle, isPresented: $showPlaceholderAlert) {
        } message: {
            Text("This action is not implemented yet.")
        }
        .alert("Reset All Data", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Everything", role: .destructive) {
                store.resetAllData()
            }
        } message: {
            Text("This removes all bills and incomes from this device. This cannot be undone.")
        }
        .sheet(isPresented: $store.showOnboardingWizard) {
            OnboardingWizardView(isPresented: $store.showOnboardingWizard)
                .environmentObject(store)
                .interactiveDismissDisabled()
        }
        .sheet(item: $touchBarActionBill) { bill in
            TouchBarBillActionsView(bill: bill) {
                touchBarActionBill = nil
            }
            .environmentObject(store)
        }
    }
    
    @ViewBuilder
    private func billDetailContent(_ bill: Bill) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if detailScreen == .info {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dueHeadline(for: bill))
                            .font(.title2.bold())
                        Text(fullDate(bill.nextDueDate))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(currency(amount: bill.amount))
                        .font(.title3.monospacedDigit())
                }
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: bill.category.symbolName)
                        Text(bill.category.rawValue.capitalized)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.15)))
                    Text(bill.recurrence.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if selectedSection != .paidRecently {
                    HStack(spacing: 12) {
                        Button("Log Payment") { store.logPayment(for: bill.id) }
                        Menu("Snooze") {
                            Button("+1 day") { store.snooze(for: bill.id, preset: .day1) }
                            Button("+3 days") { store.snooze(for: bill.id, preset: .day3) }
                            Button("+7 days") { store.snooze(for: bill.id, preset: .day7) }
                            Button("Next week") { store.snooze(for: bill.id, preset: .nextWeek) }
                            Button("End of month") { store.snooze(for: bill.id, preset: .endOfMonth) }
                            if bill.snoozeUntil != nil {
                                Button("Clear Snooze") { store.clearSnooze(for: bill.id) }
                            }
                        }
                        Button("Edit") { editingBill = bill }
                    }
                    .buttonStyle(.borderedProminent)
                    // inherit environment control size
                } else {
                    HStack(spacing: 12) {
                        Menu("Actions") {
                            Button("Log Payment") { store.logPayment(for: bill.id) }
                            Button("Edit") { editingBill = bill }
                        }
                    }
                }
                if daysUntil(bill.nextDueDate) < 0 {
                    GroupBox {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "bell.badge.fill")
                                .foregroundStyle(.red)
                                .font(.title2.weight(.bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Overdue follow‑up")
                                    .font(.headline)
                                Text("Consider contacting the bill issuer to avoid collection and confirm invoice status.")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                }
                if bill.hiddenUntilEdited {
                    GroupBox {
                        HStack {
                            Image(systemName: "eye.slash")
                            Text("Hidden from lists until edited")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Unhide Now") {
                                var updated = bill
                                updated.hiddenUntilEdited = false
                                store.update(updated)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Payments").font(.headline)
                        if bill.payments.isEmpty {
                            Text("No payments yet").foregroundStyle(.secondary)
                        } else {
                            ForEach(bill.payments.sorted(by: { $0.date > $1.date }).prefix(3)) { p in
                                HStack {
                                    Text(fullDate(p.date))
                                    Spacer()
                                    Text(currency(amount: p.amount))
                                }
                            }
                        }
                        Divider()
                        Text("Category Impact This Month").font(.headline)
                        Text(categoryImpactSummary(for: bill))
                            .foregroundStyle(.secondary)
                    }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Attachments").font(.headline)
                            Spacer()
                            Button("Add…") {
                                addAttachment(to: bill)
                            }
                            .buttonStyle(.bordered)
                        }
                        if bill.attachments.isEmpty {
                            Text("Optional: attach a PDF or image receipt/invoice.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(bill.attachments.sorted(by: { $0.createdAt > $1.createdAt })) { a in
                                HStack {
                                    Button {
                                        openAttachment(a)
                                    } label: {
                                        Text(a.displayName).lineLimit(1)
                                    }
                                    .buttonStyle(.link)
                                    Spacer()
                                    Button(role: .destructive) {
                                        removeAttachment(a, from: bill)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }
                                .font(.footnote)
                            }
                        }
                    }
                }
                GroupBox {
                    VStack(spacing: 0) {
                        Button {
                            withAnimation { detailScreen = .history }
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("View Payment History")
                                Spacer()
                                Text(historySummary(bill))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                        Button {
                            withAnimation { detailScreen = .stats }
                        } label: {
                            HStack {
                                Image(systemName: "chart.bar")
                                Text("View Statistics")
                                Spacer()
                                Text(statsSummary(bill))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if detailScreen == .history {
                HStack {
                    Button {
                        withAnimation { detailScreen = .info }
                    } label: { HStack { Image(systemName: "chevron.left"); Text("Back") } }
                    .buttonStyle(.link)
                    Spacer()
                    Text("Payment History").font(.headline)
                }
                if bill.payments.isEmpty {
                    Text("Never paid").foregroundStyle(.secondary)
                } else {
                    ForEach(bill.payments.sorted(by: { $0.date > $1.date })) { p in
                        HStack {
                            Text(fullDate(p.date))
                            Spacer()
                            Text(currency(amount: p.amount))
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else if detailScreen == .stats {
                HStack {
                    Button {
                        withAnimation { detailScreen = .info }
                    } label: { HStack { Image(systemName: "chevron.left"); Text("Back") } }
                    .buttonStyle(.link)
                    Spacer()
                    Text("Statistics").font(.headline)
                }
                let total = bill.payments.reduce(Decimal(0)) { $0 + $1.amount.value }
                let avg = bill.payments.isEmpty ? Decimal(0) : total / Decimal(bill.payments.count)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text("TOTAL PAID").bold()
                        Text(currency(from: total))
                        Text("AVERAGE").bold()
                        Text(currency(from: avg))
                    }
                }
                Divider()
                Text("TOTALS BY YEAR").bold()
                ForEach(yearTotals(bill).sorted(by: { $0.key > $1.key }), id: \.key) { year, sum in
                    HStack {
                        Text("\(year)")
                        Spacer()
                        Text(currency(from: sum))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
    
#if os(macOS)
    private func toggleSidebar() {
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
    }
#endif
    private func currency(amount: DecimalAmount) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = store.settings.displayCurrencyCode
        return nf.string(for: amount.value as NSDecimalNumber) ?? "\(amount.value)"
    }
    private func currency(from decimal: Decimal) -> String {
        let nf = NumberFormatter(); nf.numberStyle = .currency
        nf.currencyCode = store.settings.displayCurrencyCode
        return nf.string(for: decimal as NSDecimalNumber) ?? "\(decimal)"
    }
    private func fullDate(_ d: Date) -> String {
        let df = DateFormatter(); df.dateStyle = .full; return df.string(from: d)
    }
    private func daysUntil(_ date: Date) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: start, to: end).day ?? 0
    }
    private func dueHeadline(for bill: Bill) -> String {
        let d = daysUntil(bill.nextDueDate)
        if d == 0 { return "Due today" }
        if d < 0 { return "Overdue \(-d) days" }
        return "Due in \(d) days"
    }
    private func historySummary(_ bill: Bill) -> String {
        if bill.payments.isEmpty { return "Never paid" }
        return "\(bill.payments.count) payments"
    }
    private func statsSummary(_ bill: Bill) -> String {
        let total = bill.payments.reduce(Decimal(0)) { $0 + $1.amount.value }
        return currency(from: total)
    }
    private func yearTotals(_ bill: Bill) -> [Int: Decimal] {
        var dict: [Int: Decimal] = [:]
        for p in bill.payments {
            let y = Calendar.current.component(.year, from: p.date)
            dict[y, default: 0] += p.amount.value
        }
        return dict
    }
    private func categoryImpactSummary(for bill: Bill) -> String {
        let cal = Calendar.current
        let now = Date()
        let cat = bill.category
        let categoryTotal = store.bills
            .filter { $0.category == cat }
            .reduce(Decimal(0)) { sum, b in
                let paid = b.payments.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }.reduce(Decimal(0)) { $0 + $1.amount.value }
                let unpaid = (cal.isDate(b.nextDueDate, equalTo: now, toGranularity: .month) && !b.isPaidFor(date: b.nextDueDate)) ? b.amount.value : 0
                return sum + paid + unpaid
            }
        let monthTotal = store.bills.reduce(Decimal(0)) { sum, b in
            let paid = b.payments.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }.reduce(Decimal(0)) { $0 + $1.amount.value }
            let unpaid = (cal.isDate(b.nextDueDate, equalTo: now, toGranularity: .month) && !b.isPaidFor(date: b.nextDueDate)) ? b.amount.value : 0
            return sum + paid + unpaid
        }
        if monthTotal == 0 { return "No spending recorded this month" }
        let pct = (categoryTotal / monthTotal * 100).doubleValueRounded(1)
        return "\(cat.rawValue.capitalized) is \(pct)% of this month’s bills"
    }
    
    private func addAttachment(to bill: Bill) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [UTType.data, UTType.pdf, UTType.image, UTType.text]
        if panel.runModal() == .OK {
            var updated = bill
            for url in panel.urls {
                if let att = try? BillAttachmentStore.shared.save(sourceURL: url, billId: bill.id) {
                    updated.attachments.append(att)
                }
            }
            store.update(updated)
        }
        #endif
    }
    
    private func openAttachment(_ attachment: BillAttachment) {
        #if os(macOS)
        if let url = try? BillAttachmentStore.shared.resolve(attachment) {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
    
    private func removeAttachment(_ attachment: BillAttachment, from bill: Bill) {
        BillAttachmentStore.shared.delete(attachment)
        var updated = bill
        updated.attachments.removeAll(where: { $0.id == attachment.id })
        store.update(updated)
    }
}

private struct TouchBarBillActionsView: View {
    @EnvironmentObject private var store: AppStore
    let bill: Bill
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(bill.name)
                    .font(.title2.bold())
                Text("Due \(bill.nextDueDate.formatted(date: .abbreviated, time: .omitted))")
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 10) {
                Button("Log Payment") {
                    store.logPayment(for: bill.id)
                    onClose()
                }
                Button("Edit…") {
                    store.selectedBillID = bill.id
                    onClose()
                }
            }
            .buttonStyle(.borderedProminent)
            
            HStack(spacing: 10) {
                Button("Snooze +1 Day") {
                    store.snooze(for: bill.id, preset: .day1)
                    onClose()
                }
                Button("Snooze +3 Days") {
                    store.snooze(for: bill.id, preset: .day3)
                    onClose()
                }
                Button("Next Week") {
                    store.snooze(for: bill.id, preset: .nextWeek)
                    onClose()
                }
            }
            .buttonStyle(.bordered)
            
            HStack {
                Spacer()
                Button("Close") { onClose() }
                    .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}

private struct OnboardingWizardView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @State private var step: Int = 0
    
    @State private var bankEnabled: Bool = true
    @State private var bankName: String = "Bank"
    @State private var bankBalance: String = ""
    @State private var cashEnabled: Bool = false
    @State private var cashName: String = "Cash"
    @State private var cashBalance: String = ""
    
    @State private var incomeEnabled: Bool = true
    @State private var incomeName: String = "Salary"
    @State private var incomeAmount: String = ""
    @State private var incomeDay: Int = 25
    
    @State private var rentEnabled: Bool = true
    @State private var rentAmount: String = ""
    @State private var rentDay: Int = 1
    
    private struct SubDraft: Identifiable {
        let id = UUID()
        var name: String
        var amount: String
        var day: Int
    }
    @State private var subs: [SubDraft] = []
    
    @State private var goalsEnabled: Bool = false
    private struct GoalDraft: Identifiable {
        let id = UUID()
        var name: String
        var target: String
        var saved: String
        var hasTargetDate: Bool
        var targetDate: Date
    }
    @State private var goals: [GoalDraft] = []
    
    @State private var debtsEnabled: Bool = false
    private struct DebtDraft: Identifiable {
        let id = UUID()
        var name: String
        var kind: Debt.Kind
        var principal: String
        var annualRate: String
        var minimumPayment: String
        var hasDueDay: Bool
        var dueDay: Int
    }
    @State private var debts: [DebtDraft] = []
    
    @State private var budgetsEnabled: Bool = true
    @State private var budgetHousing: String = ""
    @State private var budgetSubscriptions: String = ""
    @State private var budgetUtilities: String = ""
    
    @State private var detectedLocalModels: [String] = []
    @State private var isDetectingModels: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            header()
            Divider()
            content()
                .padding(20)
            Divider()
            footer()
        }
        .frame(width: 560, height: 520)
        .background(.ultraThinMaterial)
        .onAppear {
            if subs.isEmpty {
                subs = [
                    .init(name: "Netflix", amount: "", day: 1),
                    .init(name: "Spotify", amount: "", day: 1)
                ]
            }
            if goals.isEmpty {
                goals = [
                    .init(name: "Emergency Fund", target: "", saved: "", hasTargetDate: false, targetDate: Date())
                ]
            }
            if debts.isEmpty {
                debts = [
                    .init(name: "Credit Card", kind: .creditCard, principal: "", annualRate: "", minimumPayment: "", hasDueDay: false, dueDay: 1)
                ]
            }
            if budgetHousing.isEmpty { budgetHousing = rentAmount }
            if budgetSubscriptions.isEmpty { budgetSubscriptions = sumSubs().isZero ? "" : NSDecimalNumber(decimal: sumSubs()).stringValue }
        }
    }
    
    private func header() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let url = Bundle.main.url(forResource: "logo", withExtension: "png", subdirectory: "TaskbarIcons"),
                   let img = NSImage(contentsOf: url) {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome")
                        .font(.title2.bold())
                    Text("Let’s set up your basics so dashboards and reminders make sense from day one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(step + 1) / 8")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
    }
    
    @ViewBuilder
    private func content() -> some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What you’ll get")
                            .font(.headline)
                        Text("• A clean dashboard with real numbers")
                        Text("• Budgets that reflect your categories")
                        Text("• Cash flow forecast based on your starting balance")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You can skip")
                            .font(.headline)
                        Text("You can always add or edit everything later. Setup is recommended for first use.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            }
        case 1:
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Starting Money")
                            .font(.headline)
                        Toggle("Add bank account", isOn: $bankEnabled)
                        if bankEnabled {
                            HStack {
                                TextField("Account name", text: $bankName)
                                TextField("Balance", text: $bankBalance)
                                    .frame(width: 120)
                                Text(store.settings.displayCurrencyCode)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Divider().opacity(0.2)
                        Toggle("Add cash", isOn: $cashEnabled)
                        if cashEnabled {
                            HStack {
                                TextField("Cash name", text: $cashName)
                                TextField("Balance", text: $cashBalance)
                                    .frame(width: 120)
                                Text(store.settings.displayCurrencyCode)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("This also sets the forecast starting balance.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            }
        case 2:
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Main Income")
                            .font(.headline)
                        Toggle("Add monthly income", isOn: $incomeEnabled)
                        if incomeEnabled {
                            HStack {
                                TextField("Name", text: $incomeName)
                                TextField("Amount", text: $incomeAmount)
                                    .frame(width: 120)
                                Text(store.settings.displayCurrencyCode)
                                    .foregroundStyle(.secondary)
                            }
                            Stepper("Payday: day \(incomeDay)", value: $incomeDay, in: 1...28)
                                .font(.subheadline)
                        }
                        Text("Income affects the forecast and monthly summary.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            }
        case 3:
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Core Bills")
                            .font(.headline)
                        Toggle("Add rent", isOn: $rentEnabled)
                        if rentEnabled {
                            HStack {
                                Text("Rent")
                                    .frame(width: 80, alignment: .leading)
                                TextField("Amount", text: $rentAmount)
                                    .frame(width: 120)
                                Text(store.settings.displayCurrencyCode)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Stepper("Due day \(rentDay)", value: $rentDay, in: 1...28)
                                    .font(.subheadline)
                            }
                        }
                        Divider().opacity(0.2)
                        Text("Subscriptions")
                            .font(.subheadline.weight(.semibold))
                        ForEach($subs) { $s in
                            HStack {
                                TextField("Name", text: $s.name)
                                TextField("Amount", text: $s.amount)
                                    .frame(width: 120)
                                Text(store.settings.displayCurrencyCode)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Stepper("Day \(s.day)", value: $s.day, in: 1...28)
                                    .font(.subheadline)
                            }
                        }
                        HStack {
                            Button("Add subscription") {
                                subs.append(.init(name: "Subscription", amount: "", day: 1))
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            Button("Remove last") {
                                if !subs.isEmpty { subs.removeLast() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(subs.isEmpty)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            }
        case 4:
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Goals (optional)")
                            .font(.headline)
                        Toggle("Add goals", isOn: $goalsEnabled)
                        if goalsEnabled {
                            ForEach($goals) { $g in
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("Goal name", text: $g.name)
                                    HStack {
                                        TextField("Target", text: $g.target).frame(width: 120)
                                        Text(store.settings.displayCurrencyCode).foregroundStyle(.secondary)
                                        Spacer()
                                        TextField("Saved", text: $g.saved).frame(width: 120)
                                        Text(store.settings.displayCurrencyCode).foregroundStyle(.secondary)
                                    }
                                    Toggle("Set target date", isOn: $g.hasTargetDate)
                                    if g.hasTargetDate {
                                        DatePicker("Target date", selection: $g.targetDate, displayedComponents: .date)
                                            .datePickerStyle(.field)
                                    }
                                    Divider().opacity(0.2)
                                }
                            }
                            HStack {
                                Button("Add goal") {
                                    goals.append(.init(name: "Goal", target: "", saved: "", hasTargetDate: false, targetDate: Date()))
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                                Button("Remove last") {
                                    if !goals.isEmpty { goals.removeLast() }
                                }
                                .buttonStyle(.bordered)
                                .disabled(goals.isEmpty)
                            }
                        }
                        Text("You can always edit goals later from the Goals screen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            }
        case 5:
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Debts (optional)")
                            .font(.headline)
                        Toggle("Add debts", isOn: $debtsEnabled)
                        if debtsEnabled {
                            ForEach($debts) { $d in
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("Debt name", text: $d.name)
                                    Picker("Type", selection: $d.kind) {
                                        ForEach(Debt.Kind.allCases, id: \.self) { k in
                                            Text(k.rawValue.capitalized).tag(k)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    HStack {
                                        TextField("Principal", text: $d.principal).frame(width: 120)
                                        Text(store.settings.displayCurrencyCode).foregroundStyle(.secondary)
                                        Spacer()
                                        TextField("APR %", text: $d.annualRate).frame(width: 120)
                                    }
                                    HStack {
                                        TextField("Min payment", text: $d.minimumPayment).frame(width: 120)
                                        Text(store.settings.displayCurrencyCode).foregroundStyle(.secondary)
                                        Spacer()
                                        Toggle("Due day", isOn: $d.hasDueDay)
                                    }
                                    if d.hasDueDay {
                                        Stepper("Due day \(d.dueDay)", value: $d.dueDay, in: 1...28)
                                            .font(.subheadline)
                                    }
                                    Divider().opacity(0.2)
                                }
                            }
                            HStack {
                                Button("Add debt") {
                                    debts.append(.init(name: "Debt", kind: .creditCard, principal: "", annualRate: "", minimumPayment: "", hasDueDay: false, dueDay: 1))
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                                Button("Remove last") {
                                    if !debts.isEmpty { debts.removeLast() }
                                }
                                .buttonStyle(.bordered)
                                .disabled(debts.isEmpty)
                            }
                        }
                        Text("You can always edit debts later from the Debts screen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            }
        case 6:
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("AI Command Bar Setup")
                            .font(.headline)
                        Text("The AI command bar lets you type 'spent 20 on coffee' to instantly log it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Picker("AI Engine", selection: $store.settings.aiProvider) {
                            ForEach(AppSettings.AIProvider.allCases, id: \.self) { p in
                                Text(p.rawValue.capitalized).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 4)
                        
                        if store.settings.aiProvider == .local {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Local Privacy Mode (Ollama)")
                                    .font(.subheadline.bold())
                                
                                if detectedLocalModels.isEmpty {
                                    Text("1. Download & install Ollama from **ollama.com**")
                                    Text("2. Open Terminal and run: `ollama run qwen3.5:4b`")
                                    Text("3. Keep Ollama running in the background")
                                        .foregroundStyle(.secondary)
                                    
                                    HStack {
                                        TextField("Model Name", text: $store.settings.aiModel)
                                            .textFieldStyle(.roundedBorder)
                                        Button {
                                            Task { await detectLocalModels() }
                                        } label: {
                                            if isDetectingModels {
                                                ProgressView().controlSize(.small)
                                            } else {
                                                Image(systemName: "arrow.clockwise")
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .help("Refresh models")
                                    }
                                } else {
                                    HStack {
                                        Picker("Select Model", selection: $store.settings.aiModel) {
                                            ForEach(detectedLocalModels, id: \.self) { m in
                                                Text(m).tag(m)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                        
                                        Button {
                                            Task { await detectLocalModels() }
                                        } label: {
                                            if isDetectingModels {
                                                ProgressView().controlSize(.small)
                                            } else {
                                                Image(systemName: "arrow.clockwise")
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .help("Refresh models")
                                    }
                                    Text("Ollama is running and models were detected.")
                                        .foregroundStyle(.green)
                                }
                                
                                TextField("Ollama Endpoint", text: $store.settings.aiBaseURL)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .font(.footnote)
                            .onAppear {
                                if detectedLocalModels.isEmpty {
                                    Task { await detectLocalModels() }
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("External API Mode")
                                    .font(.subheadline.bold())
                                Text("Uses cloud APIs (like Groq or OpenAI) for lightning-fast parsing.")
                                    .foregroundStyle(.secondary)
                                TextField("API Endpoint", text: $store.settings.aiExternalEndpoint)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Model Name", text: $store.settings.aiModel)
                                    .textFieldStyle(.roundedBorder)
                                SecureField("API Key (saved locally)", text: Binding(
                                    get: { store.settings.aiExternalAPIKey ?? "" },
                                    set: { store.settings.aiExternalAPIKey = $0.isEmpty ? nil : $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                            .font(.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            }
        case 7:
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Budgets (optional)")
                            .font(.headline)
                        Toggle("Enable budgets", isOn: $budgetsEnabled)
                        if budgetsEnabled {
                            HStack {
                                Text("Housing").frame(width: 120, alignment: .leading)
                                TextField("Budget", text: $budgetHousing).frame(width: 140)
                                Text(store.settings.displayCurrencyCode).foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("Subscriptions").frame(width: 120, alignment: .leading)
                                TextField("Budget", text: $budgetSubscriptions).frame(width: 140)
                                Text(store.settings.displayCurrencyCode).foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("Utilities").frame(width: 120, alignment: .leading)
                                TextField("Budget", text: $budgetUtilities).frame(width: 140)
                                Text(store.settings.displayCurrencyCode).foregroundStyle(.secondary)
                            }
                            Text("Budgets track how much you spend per category in a month.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Finish")
                            .font(.headline)
                        Text("You can edit everything later from the sidebar. This just gives you a clean first start.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            }
        default:
            EmptyView()
        }
    }
    
    private func footer() -> some View {
        HStack {
            Button("Skip for now") {
                didCompleteOnboarding = true
                isPresented = false
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer()
            Button("Back") { step = max(step - 1, 0) }
                .buttonStyle(.bordered)
                .disabled(step == 0)
            Button(step == 7 ? "Finish" : "Next") {
                if step < 7 {
                    step += 1
                } else {
                    apply()
                    didCompleteOnboarding = true
                    isPresented = false
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    private func apply() {
        let currency = store.settings.displayCurrencyCode
        var startBalance: Decimal = 0
        
        if bankEnabled, let val = Decimal(string: bankBalance.trimmingCharacters(in: .whitespaces)), val != 0 {
            let a = Account(name: bankName.isEmpty ? "Bank" : bankName, kind: .checking, currencyCode: currency, openingBalance: val, institution: nil, notes: "Added in setup", archived: false)
            store.addAccount(a)
            startBalance += val
        }
        if cashEnabled, let val = Decimal(string: cashBalance.trimmingCharacters(in: .whitespaces)), val != 0 {
            let a = Account(name: cashName.isEmpty ? "Cash" : cashName, kind: .cash, currencyCode: currency, openingBalance: val, institution: nil, notes: "Added in setup", archived: false)
            store.addAccount(a)
            startBalance += val
        }
        
        if startBalance != 0 {
            store.settings.availableBalance = startBalance
        }
        
        if incomeEnabled, let amount = Decimal(string: incomeAmount.trimmingCharacters(in: .whitespaces)), amount != 0 {
            let next = nextMonthlyDate(day: incomeDay)
            let inc = Income(name: incomeName.isEmpty ? "Salary" : incomeName, amount: .init(currencyCode: currency, value: amount), source: .salary, customSourceName: nil, recurrence: .monthly, nextPayDate: next, notes: "Added in setup", receipts: [])
            store.addIncome(inc)
        }
        
        if rentEnabled, let amount = Decimal(string: rentAmount.trimmingCharacters(in: .whitespaces)), amount != 0 {
            let due = nextMonthlyDate(day: rentDay)
            let bill = Bill(name: "Rent", amount: .init(currencyCode: currency, value: amount), category: .housing, customCategoryName: nil, recurrence: .monthly, nextDueDate: due, notes: "Added in setup", payments: [], paidAutomatically: false, hiddenUntilEdited: false)
            store.bills.append(bill)
        }
        
        for s in subs {
            let trimmed = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let amount = Decimal(string: s.amount.trimmingCharacters(in: .whitespaces)), amount != 0 else { continue }
            let due = nextMonthlyDate(day: s.day)
            let cat = AICommandParser.categoryForName(trimmed)
            let bill = Bill(name: trimmed, amount: .init(currencyCode: currency, value: amount), category: cat, customCategoryName: nil, recurrence: .monthly, nextDueDate: due, notes: "Added in setup", payments: [], paidAutomatically: false, hiddenUntilEdited: false)
            store.bills.append(bill)
        }
        
        if goalsEnabled {
            for g in goals {
                let name = g.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                guard let target = Decimal(string: g.target.trimmingCharacters(in: .whitespacesAndNewlines)), target > 0 else { continue }
                let saved = Decimal(string: g.saved.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                let goal = Goal(
                    name: name,
                    targetAmount: .init(currencyCode: currency, value: target),
                    savedAmount: .init(currencyCode: currency, value: saved),
                    targetDate: g.hasTargetDate ? g.targetDate : nil,
                    notes: "Added in setup",
                    archived: false
                )
                store.addGoal(goal)
            }
        }
        
        if debtsEnabled {
            for d in debts {
                let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                guard let principal = Decimal(string: d.principal.trimmingCharacters(in: .whitespacesAndNewlines)), principal != 0 else { continue }
                let rate = Decimal(string: d.annualRate.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                let minPay = Decimal(string: d.minimumPayment.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                let debt = Debt(
                    name: name,
                    kind: d.kind,
                    currencyCode: currency,
                    principal: principal,
                    annualInterestRate: rate,
                    minimumPayment: minPay,
                    dueDayOfMonth: d.hasDueDay ? d.dueDay : nil,
                    notes: "Added in setup",
                    archived: false
                )
                store.addDebt(debt)
            }
        }
        
        if budgetsEnabled {
            setBudget(cat: .housing, value: budgetHousing)
            setBudget(cat: .subscriptions, value: budgetSubscriptions)
            setBudget(cat: .utilities, value: budgetUtilities)
        } else {
            store.settings.monthlyBudgets.removeAll()
        }
        
        // AI Settings are already bound directly to store.settings via Bindings, so they are saved automatically when modified in setup.
        // We just need to trigger the setter to save to UserDefaults.
        store.settings = store.settings
    }
    
    private func setBudget(cat: Bill.Category, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = AppSettings.budgetKey(builtin: cat)
        if trimmed.isEmpty {
            store.settings.monthlyBudgets.removeValue(forKey: key)
            return
        }
        if let d = Decimal(string: trimmed), d > 0 {
            store.settings.monthlyBudgets[key] = d
        }
    }
    
    private func sumSubs() -> Decimal {
        subs.reduce(Decimal(0)) { acc, s in
            guard let v = Decimal(string: s.amount.trimmingCharacters(in: .whitespacesAndNewlines)) else { return acc }
            return acc + v
        }
    }
    
    private func nextMonthlyDate(day: Int) -> Date {
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
    
    private func detectLocalModels() async {
        isDetectingModels = true
        defer { isDetectingModels = false }
        
        let base = store.settings.aiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/api/tags") else { return }
        
        var req = URLRequest(url: url)
        req.timeoutInterval = 3.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            
            struct OllamaTagsResponse: Decodable {
                struct Model: Decodable {
                    let name: String
                }
                let models: [Model]
            }
            
            let res = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            let names = res.models.map { $0.name }
            
            await MainActor.run {
                self.detectedLocalModels = names
                if !names.isEmpty && !names.contains(store.settings.aiModel) {
                    store.settings.aiModel = names[0]
                }
            }
        } catch {
            // failed to connect, leave as empty
            await MainActor.run {
                self.detectedLocalModels = []
            }
        }
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case income = "Income"
    case accounts = "Accounts"
    case transactions = "Legacy Transactions"
    case goals = "Goals"
    case debts = "Debts"
    case dueSoon = "Due Soon"
    case dueThisMonth = "Due This Month"
    case monthlySummary = "Monthly Summary"
    case deferred = "Deferred"
    case paidRecently = "Transactions"
    case reports = "Reports"
    case settings = "Settings"
    var id: String { rawValue }
}
