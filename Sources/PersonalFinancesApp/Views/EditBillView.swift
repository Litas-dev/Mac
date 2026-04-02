import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct EditBillView: View {
    var bill: Bill
    var onSave: (Bill) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var name: String
    @State private var amount: String
    @State private var dueDate: Date
    @State private var recurrence: Recurrence
    @State private var category: Bill.Category
    @State private var notes: String
    // Removed: amountVaries, Payment URL, Tags, Currency input
    @State private var paidAutomatically: Bool = false
    @State private var enableReminder: Bool = false
    @State private var reminderDays: Int = 7
    @State private var showMiniCalendar: Bool = false
    @State private var attachments: [BillAttachment]
    @State private var attachmentError: String? = nil

    init(bill: Bill, onSave: @escaping (Bill) -> Void) {
        self.bill = bill
        self.onSave = onSave
        _name = State(initialValue: bill.name)
        _amount = State(initialValue: NSDecimalNumber(decimal: bill.amount.value).stringValue)
        _dueDate = State(initialValue: bill.nextDueDate)
        _recurrence = State(initialValue: bill.recurrence)
        _category = State(initialValue: bill.category)
        _notes = State(initialValue: bill.notes ?? "")
        _paidAutomatically = State(initialValue: bill.paidAutomatically)
        _attachments = State(initialValue: bill.attachments)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Bill Name")
                        .font(.title.bold())
                    HStack(spacing: 8) {
                        Image(systemName: category.symbolName)
                            .font(.title2)
                        TextField("Home, Mortgage & Rent", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                        Spacer()
                        Picker("", selection: $category) {
                            ForEach(Bill.Category.allCases, id: \.self) { c in
                                Text(c.rawValue.capitalized).tag(c)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Divider()
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text("Next Due Date").frame(width: 140, alignment: .leading)
                            HStack(spacing: 8) {
                                DatePicker("", selection: $dueDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                Button {
                                    showMiniCalendar.toggle()
                                } label: {
                                    Label("View", systemImage: "calendar")
                                }
                                .buttonStyle(.bordered)
                                .popover(isPresented: $showMiniCalendar) {
                                    MiniMonthPicker(date: $dueDate) { _ in
                                        showMiniCalendar = false
                                    }
                                }
                            }
                        }
                        GridRow {
                            Text("Repeat Interval").frame(width: 140, alignment: .leading)
                            Picker("", selection: $recurrence) {
                                ForEach(Recurrence.allCases, id: \.self) { r in
                                    Text(r.rawValue.capitalized).tag(r)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        GridRow {
                            Text("Amount Due").frame(width: 140, alignment: .leading)
                            HStack(spacing: 8) {
                                TextField("Amount", text: $amount)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)
                            }
                        }
                        GridRow {
                            Text("").frame(width: 140)
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Paid Automatically", isOn: $paidAutomatically)
                                Toggle("Enable Reminder", isOn: $enableReminder)
                                HStack(spacing: 8) {
                                    TextField("", value: $reminderDays, formatter: NumberFormatter())
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 56)
                                        .disabled(!enableReminder)
                                    Text("days before due")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.leading, 2)
                            }
                        }
                        GridRow {
                            Text("Notes").frame(width: 140, alignment: .leading)
                            TextEditor(text: $notes)
                                .frame(minHeight: 72)
                                .padding(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.25))
                                )
                        }
                        GridRow {
                            Text("Attachments").frame(width: 140, alignment: .leading)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Button("Add…") { addAttachment() }
                                        .buttonStyle(.bordered)
                                }
                                if attachments.isEmpty {
                                    Text("Optional: attach a PDF or image receipt/invoice.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(attachments) { a in
                                                HStack {
                                                    Button {
                                                        openAttachment(a)
                                                    } label: {
                                                        Text(a.displayName)
                                                            .lineLimit(1)
                                                    }
                                                    .buttonStyle(.link)
                                                    Spacer()
                                                    Button(role: .destructive) {
                                                        removeAttachment(a)
                                                    } label: {
                                                        Image(systemName: "trash")
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                                .font(.footnote)
                                            }
                                        }
                                    }
                                    .frame(maxHeight: 110)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            Divider().opacity(0.2)
            HStack {
                Button("Delete") {
                    if let idx = store.bills.firstIndex(where: { $0.id == bill.id }) {
                        for a in store.bills[idx].attachments {
                            BillAttachmentStore.shared.delete(a)
                        }
                        store.bills.remove(at: idx)
                    }
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") {
                    guard let dec = Decimal(string: amount), !name.isEmpty else { return }
                    var updated = bill
                    updated.name = name
                    updated.amount = .init(currencyCode: bill.amount.currencyCode, value: dec)
                    updated.category = category
                    updated.recurrence = recurrence
                    updated.nextDueDate = dueDate
                    updated.notes = notes.isEmpty ? nil : notes
                    updated.paidAutomatically = paidAutomatically
                    updated.hiddenUntilEdited = false
                    updated.attachments = attachments
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 640, height: 440)
        .alert("Attachment Error", isPresented: Binding(get: { attachmentError != nil }, set: { _ in attachmentError = nil })) {
            Button("OK") { attachmentError = nil }
        } message: {
            Text(attachmentError ?? "")
        }
    }
    
    private func addAttachment() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [UTType.data, UTType.pdf, UTType.image, UTType.text]
        if panel.runModal() == .OK {
            for url in panel.urls {
                do {
                    let att = try BillAttachmentStore.shared.save(sourceURL: url, billId: bill.id)
                    attachments.append(att)
                } catch {
                    attachmentError = error.localizedDescription
                }
            }
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
    
    private func removeAttachment(_ attachment: BillAttachment) {
        BillAttachmentStore.shared.delete(attachment)
        attachments.removeAll(where: { $0.id == attachment.id })
    }
}
