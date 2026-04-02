import SwiftUI
import UniformTypeIdentifiers

struct MonthlySummaryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedMonth = Date()
    @State private var selectedBillRowID: UUID? = nil
    @State private var selectedIncomeRowID: UUID? = nil
    var onEditBill: ((Bill) -> Void)? = nil
    var onEditIncome: ((Income) -> Void)? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Monthly Cash Flow")
                        .font(.largeTitle.bold())
                    Spacer()
                    Button { exportPDF() } label: {
                        Label("Export PDF", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    DatePicker("", selection: $selectedMonth, displayedComponents: .date)
                        .datePickerStyle(.stepperField)
                        .labelsHidden()
                        .frame(width: 150)
                }
                
                let summary = calculateSummary(for: selectedMonth)
                
                // KPI Cards
                HStack(spacing: 16) {
                    SummaryCard(title: "Expected Income", value: currency(summary.income), color: .green)
                    SummaryCard(title: "Expected Bills", value: currency(summary.bills), color: .red)
                    SummaryCard(title: "Expected Net", value: currency(summary.net), color: summary.net >= 0 ? .blue : .orange)
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Income").font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        let received = summary.incomeDetails.filter { $0.isPaid }
                        let expected = summary.incomeDetails.filter { !$0.isPaid }
                        
                        if !expected.isEmpty {
                            Text("Expected").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            VStack(spacing: 0) {
                                ForEach(expected) { item in
                                    let isSelected = (selectedIncomeRowID == item.id)
                                    CashFlowRow(
                                        name: item.name,
                                        date: item.date,
                                        amountText: currency(item.amount),
                                        statusText: "Expected",
                                        statusColor: .orange,
                                        actionTitle: "Edit",
                                        actionRole: .none,
                                        onAction: {
                                            if let id = item.incomeID {
                                                if let inc = store.incomes.first(where: { $0.id == id }) {
                                                    onEditIncome?(inc)
                                                }
                                            }
                                        }
                                    )
                                    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedIncomeRowID = item.id
                                        selectedBillRowID = nil
                                        store.selectedBillID = nil
                                        if let id = item.incomeID {
                                            store.selectedIncomeID = id
                                        }
                                    }
                                    Divider()
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.05)))
                        }
                        
                        if !received.isEmpty {
                            Text("Received").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            VStack(spacing: 0) {
                                ForEach(received) { item in
                                    let isSelected = (selectedIncomeRowID == item.id)
                                    CashFlowRow(
                                        name: item.name,
                                        date: item.date,
                                        amountText: currency(item.amount),
                                        statusText: "Received",
                                        statusColor: .green
                                    )
                                    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedIncomeRowID = item.id
                                        selectedBillRowID = nil
                                        store.selectedBillID = nil
                                        if let id = item.incomeID {
                                            store.selectedIncomeID = id
                                        }
                                    }
                                    Divider()
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.05)))
                        }
                        
                        if expected.isEmpty && received.isEmpty {
                            Text("No income items for this month.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Bills").font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        let paid = summary.billDetails.filter { $0.isPaid }
                        let due = summary.billDetails.filter { !$0.isPaid }
                        
                        if !due.isEmpty {
                            Text("Due").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            VStack(spacing: 0) {
                                ForEach(due) { item in
                                    let isSelected = (selectedBillRowID == item.id)
                                    CashFlowRow(
                                        name: item.name,
                                        date: item.date,
                                        amountText: currency(item.amount),
                                        statusText: "Due",
                                        statusColor: .orange,
                                        actionTitle: "Edit",
                                        actionRole: .none,
                                        onAction: {
                                            if let id = item.billID {
                                                if let bill = store.bills.first(where: { $0.id == id }) {
                                                    onEditBill?(bill)
                                                }
                                            }
                                        }
                                    )
                                    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedBillRowID = item.id
                                        selectedIncomeRowID = nil
                                        store.selectedIncomeID = nil
                                        if let id = item.billID {
                                            store.selectedBillID = id
                                        }
                                    }
                                    Divider()
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.05)))
                        }
                        
                        if !paid.isEmpty {
                            Text("Paid").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            VStack(spacing: 0) {
                                ForEach(paid) { item in
                                    let isSelected = (selectedBillRowID == item.id)
                                    CashFlowRow(
                                        name: item.name,
                                        date: item.date,
                                        amountText: currency(item.amount),
                                        statusText: "Paid",
                                        statusColor: .green
                                    )
                                    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedBillRowID = item.id
                                        selectedIncomeRowID = nil
                                        store.selectedIncomeID = nil
                                        if let id = item.billID {
                                            store.selectedBillID = id
                                        }
                                    }
                                    Divider()
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.05)))
                        }
                        
                        if due.isEmpty && paid.isEmpty {
                            Text("No bill items for this month.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    private func calculateSummary(for month: Date) -> MonthSummary {
        let cal = Calendar.current
        var income: Decimal = 0
        var bills: Decimal = 0
        var incomeDetails: [SummaryItem] = []
        var billDetails: [SummaryItem] = []
        
        // Income
        for inc in store.incomes {
            // Received payments this month
            for p in inc.receipts {
                if cal.isDate(p.date, equalTo: month, toGranularity: .month) {
                    income += p.amount.value
                    incomeDetails.append(SummaryItem(name: inc.name, amount: p.amount.value, date: p.date, isPaid: true, incomeID: inc.id))
                }
            }
            // Upcoming payments this month
            if cal.isDate(inc.nextPayDate, equalTo: month, toGranularity: .month) {
                if !inc.receipts.contains(where: { cal.isDate($0.date, inSameDayAs: inc.nextPayDate) }) {
                    income += inc.amount.value
                    incomeDetails.append(SummaryItem(name: inc.name, amount: inc.amount.value, date: inc.nextPayDate, isPaid: false, incomeID: inc.id))
                }
            }
        }
        
        // Bills
        for bill in store.bills {
            // Paid bills this month
            for p in bill.payments {
                if cal.isDate(p.date, equalTo: month, toGranularity: .month) {
                    bills += p.amount.value
                    billDetails.append(SummaryItem(name: bill.name, amount: p.amount.value, date: p.date, isPaid: true, billID: bill.id))
                }
            }
            // Unpaid bills this month
            if cal.isDate(bill.nextDueDate, equalTo: month, toGranularity: .month) && !bill.isPaidFor(date: bill.nextDueDate) {
                bills += bill.amount.value
                billDetails.append(SummaryItem(name: bill.name, amount: bill.amount.value, date: bill.nextDueDate, isPaid: false, billID: bill.id))
            }
        }
        
        return MonthSummary(
            income: income,
            bills: bills,
            net: income - bills,
            incomeDetails: incomeDetails.sorted(by: { $0.date < $1.date }),
            billDetails: billDetails.sorted(by: { $0.date < $1.date })
        )
    }
    
    private func currency(_ value: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = store.settings.displayCurrencyCode
        return nf.string(for: value as NSDecimalNumber) ?? "\(value)"
    }
    
    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let df = DateFormatter(); df.dateFormat = "yyyy-MM"
        panel.nameFieldStringValue = "Monthly_Summary_\(df.string(from: selectedMonth)).pdf"
        
        if panel.runModal() == .OK, let url = panel.url {
            let summary = calculateSummary(for: selectedMonth)
            let view = PDFExportView(month: selectedMonth, summary: summary, currency: currency, currencyCode: store.settings.displayCurrencyCode)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = .init(CGSize(width: 595, height: 842))
            renderer.render { size, context in
                var box = CGRect(origin: .zero, size: size)
                guard let pdfContext = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
                pdfContext.beginPDFPage(nil)
                context(pdfContext)
                pdfContext.endPDFPage()
                pdfContext.closePDF()
            }
        }
    }
}

struct PDFExportView: View {
    let month: Date
    let summary: MonthSummary
    let currency: (Decimal) -> String
    let currencyCode: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header()
            kpis()
            HStack(alignment: .top, spacing: 14) {
                sectionTable(title: "Income", items: summary.incomeDetails, kind: .income)
                sectionTable(title: "Bills", items: summary.billDetails, kind: .bill)
            }
            Spacer(minLength: 0)
            footer()
        }
        .frame(width: 595, height: 842, alignment: .topLeading)
        .padding(.horizontal, 44)
        .padding(.vertical, 40)
        .background(Color.white)
        .foregroundStyle(.black)
    }

    private enum TableKind { case income, bill }

    private func header() -> some View {
        let monthText = month.formatted(.dateTime.month(.wide).year())
        let gen = Date().formatted(date: .abbreviated, time: .shortened)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "wallet.pass")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Personal Finances")
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.2)
                    }
                    Text("Monthly Summary")
                        .font(.system(size: 24, weight: .bold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(monthText)
                        .font(.system(size: 13, weight: .semibold))
                    Text("Generated \(gen)")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                }
            }
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func kpis() -> some View {
        HStack(spacing: 10) {
            kpiBox(title: "Total Income", value: currency(summary.income), accent: .green)
            kpiBox(title: "Total Bills", value: currency(summary.bills), accent: .red)
            kpiBox(title: "Net", value: currency(summary.net), accent: summary.net >= 0 ? .blue : .orange)
        }
    }

    private func kpiBox(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accent)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private func sectionTable(title: String, items: [SummaryItem], kind: TableKind) -> some View {
        let maxRows = 18
        let shown = Array(items.prefix(maxRows))
        let remaining = max(0, items.count - shown.count)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                if remaining > 0 {
                    Text("+\(remaining) more")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.gray)
                }
            }
            tableHeader()
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { idx, item in
                    tableRow(item, zebra: idx % 2 == 1, kind: kind)
                }
                if shown.isEmpty {
                    HStack {
                        Text("No items")
                            .font(.system(size: 11))
                            .foregroundStyle(.gray)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableHeader() -> some View {
        HStack(spacing: 10) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Date")
                .frame(width: 78, alignment: .leading)
            Text("Status")
                .frame(width: 58, alignment: .leading)
            Text(currencyCode)
                .frame(width: 80, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.gray)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func tableRow(_ item: SummaryItem, zebra: Bool, kind: TableKind) -> some View {
        let statusText: String = {
            switch kind {
            case .income: return item.isPaid ? "Received" : "Pending"
            case .bill: return item.isPaid ? "Paid" : "Due"
            }
        }()
        let statusColor: Color = item.isPaid ? .green : .orange
        return HStack(spacing: 10) {
            Text(item.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.date.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 10))
                .foregroundStyle(.gray)
                .frame(width: 78, alignment: .leading)
            Text(statusText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 58, alignment: .leading)
            Text(currency(item.amount))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(zebra ? Color.black.opacity(0.02) : Color.white)
    }

    private func footer() -> some View {
        HStack {
            Text("Personal Finances • Monthly Summary")
                .font(.system(size: 9))
                .foregroundStyle(.gray)
            Spacer()
            Text("Confidential")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.gray)
        }
        .padding(.top, 10)
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1),
            alignment: .top
        )
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title.bold()).monospacedDigit().foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(color.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.2), lineWidth: 1))
    }
}

struct DetailRow: View {
    let name: String
    let amount: Decimal
    let date: Date
    let isPaid: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.body.weight(.medium))
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(NSDecimalNumber(decimal: amount).stringValue).monospacedDigit()
                Text(isPaid ? "Received/Paid" : "Pending")
                    .font(.caption)
                    .foregroundStyle(isPaid ? .green : .orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct MonthSummary {
    let income: Decimal
    let bills: Decimal
    let net: Decimal
    let incomeDetails: [SummaryItem]
    let billDetails: [SummaryItem]
}

struct SummaryItem: Identifiable {
    let id: UUID
    let name: String
    let amount: Decimal
    let date: Date
    let isPaid: Bool
    let billID: UUID?
    let incomeID: UUID?
    
    init(name: String, amount: Decimal, date: Date, isPaid: Bool, billID: UUID? = nil, incomeID: UUID? = nil) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.date = date
        self.isPaid = isPaid
        self.billID = billID
        self.incomeID = incomeID
    }
}

private struct CashFlowRow: View {
    let name: String
    let date: Date
    let amountText: String
    let statusText: String
    let statusColor: Color
    var actionTitle: String? = nil
    var actionRole: ButtonRole? = nil
    var onAction: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.body.weight(.medium))
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(amountText).monospacedDigit()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            if let actionTitle, let onAction {
                Button(role: actionRole) {
                    onAction()
                } label: {
                    Text(actionTitle)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
