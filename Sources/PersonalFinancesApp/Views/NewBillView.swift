import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct NewBillView: View {
    var onCreate: (Bill) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var amount: String = ""
    @EnvironmentObject private var store: AppStore
    @State private var currency: String = (Locale.current.currency?.identifier) ?? "USD"
    @State private var dueDate: Date = Date()
    @State private var recurrence: Recurrence = .monthly
    @State private var category: Bill.Category = .other
    @State private var notes: String = ""
    @State private var paidAutomatically: Bool = false
    @State private var enableReminder: Bool = true
    @State private var reminderDays: Int = 7
    @State private var showMiniCalendar: Bool = false
    @State private var pendingAttachmentURLs: [URL] = []
    @State private var attachmentError: String? = nil

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
                                    if !pendingAttachmentURLs.isEmpty {
                                        Button("Clear") { pendingAttachmentURLs.removeAll() }
                                            .buttonStyle(.bordered)
                                    }
                                }
                                if pendingAttachmentURLs.isEmpty {
                                    Text("Optional: attach a PDF or image receipt/invoice.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(Array(pendingAttachmentURLs.enumerated()), id: \.offset) { _, url in
                                                HStack {
                                                    Text(url.lastPathComponent)
                                                        .lineLimit(1)
                                                    Spacer()
                                                    Button(role: .destructive) {
                                                        pendingAttachmentURLs.removeAll(where: { $0 == url })
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
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") {
                    guard let dec = Decimal(string: amount), !name.isEmpty else { return }
                    var bill = Bill(
                        name: name,
                        amount: .init(currencyCode: (currency.isEmpty ? store.settings.displayCurrencyCode : currency).uppercased(), value: dec),
                        category: category,
                        recurrence: recurrence,
                        nextDueDate: dueDate,
                        notes: notes.isEmpty ? nil : notes,
                        payments: [],
                        paidAutomatically: paidAutomatically
                    )
                    if !pendingAttachmentURLs.isEmpty {
                        var created: [BillAttachment] = []
                        for url in pendingAttachmentURLs {
                            if let att = try? BillAttachmentStore.shared.save(sourceURL: url, billId: bill.id) {
                                created.append(att)
                            }
                        }
                        bill.attachments = created
                        pendingAttachmentURLs.removeAll()
                    }
                    onCreate(bill)
                    if enableReminder && store.settings.enableNotifications {
                        NotificationManager.shared.requestAuthorization { granted in
                            if granted {
                                NotificationManager.shared.schedule(for: bill, settings: store.settings)
                            }
                        }
                    }
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
                if !pendingAttachmentURLs.contains(url) {
                    pendingAttachmentURLs.append(url)
                }
            }
        }
        #endif
    }
}
