import SwiftUI

#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct BankCSVImportSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var plan: BankCSVImporter.ImportPlan? = nil
    @State private var isLoading: Bool = false
    @State private var createAccounts: Bool = true
    @State private var errorMessage: String? = nil
    @State private var resultMessage: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Import Bank CSV")
                    .font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }
            
            HStack(spacing: 10) {
                Button("Choose CSV files…") { chooseFiles() }
                    .buttonStyle(.borderedProminent)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                if plan != nil {
                    Button("Clear") {
                        plan = nil
                        errorMessage = nil
                        resultMessage = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            if let msg = errorMessage, !msg.isEmpty {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            
            if let msg = resultMessage, !msg.isEmpty {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    if let p = plan {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Files: \(p.files.count) • Transactions: \(p.transactions.count) • Accounts found: \(p.detectedAccounts.count)")
                                .foregroundStyle(.secondary)
                            if let a = p.dateMin, let b = p.dateMax {
                                Text("Range: \(a.formatted(date: .abbreviated, time: .omitted)) → \(b.formatted(date: .abbreviated, time: .omitted))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.footnote)
                        
                        Toggle("Create accounts found in CSV", isOn: $createAccounts)
                        
                        if !p.detectedAccounts.isEmpty {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(p.detectedAccounts, id: \.normalizedNumber) { a in
                                        HStack {
                                            Text(a.name)
                                            Spacer()
                                            Text(a.displayNumber)
                                                .foregroundStyle(.secondary)
                                        }
                                        .font(.footnote)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 160)
                        }
                    } else {
                        Text("Choose one or more CSV files to preview what will be imported.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Import") {
                    importNow()
                }
                .buttonStyle(.borderedProminent)
                .disabled(plan == nil || isLoading || (plan?.transactions.isEmpty ?? true))
            }
        }
        .padding(18)
        .frame(width: 560, height: 520)
        #if os(macOS)
        .draggableWindow()
        #endif
    }
    
    private func chooseFiles() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText, UTType.plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task {
                await MainActor.run {
                    isLoading = true
                    errorMessage = nil
                    resultMessage = nil
                }
                do {
                    let parsed = try await Task.detached { try BankCSVImporter.makePlan(urls: urls) }.value
                    await MainActor.run {
                        plan = parsed
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                    }
                }
                await MainActor.run {
                    isLoading = false
                }
            }
        }
        #endif
    }
    
    private func importNow() {
        guard let plan else { return }
        isLoading = true
        errorMessage = nil
        resultMessage = nil
        
        Task { @MainActor in
            let result = BankCSVImportEngine.apply(plan: plan, store: store, createAccounts: createAccounts)
            isLoading = false
            if result.importedTransactions == 0 {
                resultMessage = "No new transactions were imported."
                return
            }
            resultMessage = "Imported \(result.importedTransactions) transactions • Created \(result.createdAccounts) accounts • Skipped \(result.skippedDuplicates) duplicates"
        }
    }
}

