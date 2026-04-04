import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AICommandBarView: View {
    @EnvironmentObject private var store: AppStore
    let resetToken: UUID
    @State private var input: String = ""
    @State private var preview: String? = nil
    @State private var parseError: String? = nil
    @State private var parsed: AIParsedCommand? = nil
    @State private var isLoading = false
    @State private var success: String? = nil
    @State private var errorToken: UUID? = nil
    @State private var lastErrorMessage: String? = nil
    @State private var suppressErrorsUntilInputChange: Bool = false
    @FocusState private var inputFocused: Bool
    @State private var suggestions: [CommandMemoryEntry] = []
    @State private var favorites: [CommandMemoryEntry] = []
    @State private var lastParsedInput: String = ""
    @State private var showPanel: Bool = false
    @State private var showSuggestions: Bool = false
    @State private var ignoreNextInputChangeReset: Bool = false
    private enum ProviderStatus { case unknown, loading, ok, offline }
    @State private var providerStatus: ProviderStatus = .unknown
    
    init(resetToken: UUID = UUID()) {
        self.resetToken = resetToken
    }
    private func makeParser() -> AICommandParser {
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
        let cfg = AICommandParser.Config(endpoint: url, model: store.settings.aiModel, timeout: 20, provider: provider, apiKey: store.settings.aiExternalAPIKey)
        return AICommandParser(config: cfg)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            TextField("Command…", text: $input, onCommit: { Task { await runParse() } })
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .focused($inputFocused)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1).padding(.vertical, 6)
            Button {
                if suggestions.isEmpty {
                    suggestions = CommandMemoryStore.shared.recents()
                }
                showSuggestions.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(.plain)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1).padding(.vertical, 6)
            Button { Task { await runParse() } } label: {
                Group {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Parse")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .frame(width: 68, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            .popover(isPresented: $showPanel, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    if let err = parseError {
                        Text("Error").font(.headline)
                        Text(err).foregroundStyle(.secondary)
                        HStack {
                            Spacer()
                            Button("Close") {
                                parseError = nil
                                showPanel = false
                            }
                        }
                    } else if let p = preview {
                        Text("Review").font(.headline)
                        Text(p).foregroundStyle(.secondary)
                        HStack {
                            Button("Confirm") { confirm() }.buttonStyle(.borderedProminent)
                            Button("Cancel") {
                                preview = nil
                                parsed = nil
                                showPanel = false
                                inputFocused = false
                            }
                        }
                    } else if let ok = success {
                        Text("Done").font(.headline)
                        Text(ok).foregroundStyle(.secondary)
                        HStack {
                            Spacer()
                            Button("Close") {
                                success = nil
                                showPanel = false
                                inputFocused = false
                            }
                        }
                    } else {
                        Text("No details").foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(width: 420)
            }
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1).padding(.vertical, 6)
            Circle()
                .fill(statusColor())
                .frame(width: 8, height: 8)
                .frame(width: 24, height: 28)
                .help(statusHelp())
        }
        .frame(height: 28)
        .frame(maxWidth: 460, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            if suggestions.isEmpty {
                suggestions = CommandMemoryStore.shared.recents()
            }
            inputFocused = true
            showSuggestions = true
        }
        .popover(isPresented: $showSuggestions, arrowEdge: .top) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 8) {
                    if suggestions.isEmpty {
                        Text("No recent commands yet.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(suggestions) { s in
                            Button {
                                ignoreNextInputChangeReset = true
                                parsed = s.command
                                preview = makePreview(for: s.command)
                                input = s.input
                                showSuggestions = false
                                showPanel = true
                            } label: {
                                HStack(spacing: 8) {
                                    Text(label(for: s.command))
                                    Spacer()
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(10)
            }
            .frame(width: 420, height: 180)
        }
        .onAppear { refreshFavorites() }
        .onChange(of: showPanel) { newValue in
            if !newValue, preview != nil || parseError != nil || success != nil {
                preview = nil
                parseError = nil
                success = nil
                parsed = nil
            }
        }
        .onChange(of: resetToken) { _ in
            clearAndDismiss()
        }
        .onChange(of: input) { _ in
            if ignoreNextInputChangeReset {
                ignoreNextInputChangeReset = false
            } else {
                parseError = nil
                success = nil
                preview = nil
                parsed = nil
                suppressErrorsUntilInputChange = false
                lastErrorMessage = nil
                showPanel = false
            }
            suggestions = CommandMemoryStore.shared.suggestions(for: input)
            showSuggestions = inputFocused
            refreshFavorites()
        }
        .onChange(of: inputFocused) { focused in
            if focused {
                suggestions = CommandMemoryStore.shared.recents()
                showSuggestions = true
            } else {
                showSuggestions = false
            }
            refreshFavorites()
        }
    }
    
    @MainActor
    private func runParse() async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearAndDismiss()
            input = ""
            return
        }
        isLoading = true; parseError = nil; preview = nil; parsed = nil; success = nil; providerStatus = .loading
        do {
            let cmd = try await makeParser().parse(userInput: input)
            lastParsedInput = input
            if let err = store.validate(command: cmd) {
                showError("Could not understand: \(err)")
                providerStatus = .ok
                showPanel = true
            } else {
                parsed = cmd
                preview = makePreview(for: cmd)
                providerStatus = .ok
                showPanel = true
            }
        } catch {
            if let e = error as? AICommandParser.AICommandParserError {
                switch e {
                case .localNotRunning:
                    showError("Local AI is not running. Start Ollama, or switch AI Provider to External in Settings.")
                    providerStatus = .offline
                case .requestTimedOut:
                    showError("AI request timed out. Check the model/server and try again.")
                    providerStatus = .offline
                case .externalAPIKeyMissing:
                    showError("External AI needs an API key. Add it in Settings → AI, or switch to Local.")
                    providerStatus = .offline
                case .externalUnauthorized:
                    showError("External AI authorization failed. Check your API key.")
                    providerStatus = .offline
                case .badStatus(let code):
                    showError("AI server returned an error (\(code)).")
                    providerStatus = .offline
                case .invalidResponse:
                    showError("AI server returned an invalid response.")
                    providerStatus = .offline
                }
            } else {
                showError("AI error. Check your AI settings and try again.")
                providerStatus = .offline
            }
            showPanel = true
        }
        isLoading = false
        refreshFavorites()
    }
    
    @MainActor
    private func showError(_ msg: String) {
        if suppressErrorsUntilInputChange, lastErrorMessage == msg {
            return
        }
        parseError = msg
        let token = UUID(); errorToken = token
        lastErrorMessage = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if errorToken == token {
                parseError = nil
                suppressErrorsUntilInputChange = true
            }
        }
    }
    private func makePreview(for cmd: AIParsedCommand) -> String {
        switch cmd.type {
        case .income:
            let amt = cmd.amount ?? 0
            let name = cmd.name ?? "Income"
            if let rec = cmd.recurrence, rec == "monthly" {
                let day = cmd.dueDay ?? 1
                return "Schedule income: \(store.settings.displayCurrencyCode) \(amt) → \(name), monthly day \(day)"
            }
            if let d = cmd.date { return "Log income: \(store.settings.displayCurrencyCode) \(amt) → \(name) on \(d)" }
            return "Log income: \(store.settings.displayCurrencyCode) \(amt) → \(name)" 
        case .expense:
            let amt = cmd.amount ?? 0
            return "Log expense: \(store.settings.displayCurrencyCode) \(amt) → \(cmd.category ?? "Other")"
        case .send_invoice:
            return "Send invoice to: \(cmd.contact ?? "")"
        case .pay_bill:
            if let a = cmd.amount { return "Pay bill: \(cmd.bill ?? "") with \(store.settings.displayCurrencyCode) \(a)" }
            return "Pay bill: \(cmd.bill ?? "")"
        case .reminder:
            return "Reminder: \(cmd.text ?? "") @ \(cmd.date ?? "")"
        case .error:
            return "Unknown command"
        }
    }
    @MainActor
    private func confirm() {
        guard let cmd = parsed else { return }
        switch cmd.type {
        case .income:
            let message = store.execute(command: cmd)
            completeSuccess(message: message, cmd: cmd, fallbackInput: "income")
        case .send_invoice, .reminder:
            parseError = "Action not implemented yet"
            preview = nil
            success = nil
            showPanel = true
            return
        case .expense, .pay_bill:
            let message = store.execute(command: cmd)
            completeSuccess(message: message, cmd: cmd, fallbackInput: "command")
        case .error:
            parseError = "Unknown command"
        }
    }
    
    @MainActor
    private func completeSuccess(message: String, cmd: AIParsedCommand, fallbackInput: String) {
        preview = nil
        parseError = nil
        parsed = nil
        showPanel = false
        showSuggestions = false
        success = "Done: \(message)"
        input = ""
        resignInputFocus()
        CommandMemoryStore.shared.record(input: lastParsedInput.isEmpty ? fallbackInput : lastParsedInput, command: cmd)
        lastParsedInput = ""
        suggestions = CommandMemoryStore.shared.recents()
        refreshFavorites()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            success = nil
        }
    }
    
    @MainActor
    private func clearAndDismiss() {
        isLoading = false
        preview = nil
        parseError = nil
        parsed = nil
        success = nil
        errorToken = nil
        lastErrorMessage = nil
        suppressErrorsUntilInputChange = false
        showPanel = false
        showSuggestions = false
        resignInputFocus()
    }
    
    @MainActor
    private func resignInputFocus() {
        inputFocused = false
        #if os(macOS)
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
            NotificationCenter.default.post(name: NSNotification.Name("RestoreTouchBarResponder"), object: nil)
        }
        #endif
    }
    @MainActor
    private func refreshFavorites() {
        let rec = CommandMemoryStore.shared.recents(limit: 12)
        favorites = rec.filter { $0.favorite }
    }
    private func label(for cmd: AIParsedCommand) -> String {
        switch cmd.type {
        case .expense:
            let c = cmd.category ?? "Other"
            let a = cmd.amount?.description ?? ""
            return "Expense • \(c) • \(a)"
        case .income:
            let n = cmd.name ?? "Income"
            if cmd.recurrence == "monthly" {
                let d = cmd.dueDay ?? 1
                return "Income • \(n) • monthly d\(d)"
            }
            return "Income • \(n)"
        case .pay_bill:
            let b = cmd.bill ?? "Bill"
            if cmd.recurrence == "monthly" {
                let d = cmd.dueDay ?? 1
                return "Bill • \(b) • monthly d\(d)"
            }
            return "Bill • \(b)"
        case .reminder:
            return "Reminder"
        case .send_invoice:
            return "Send invoice"
        case .error:
            return "Unknown"
        }
    }
    private func statusColor() -> Color {
        switch providerStatus {
        case .unknown: return .secondary.opacity(0.5)
        case .loading: return .orange
        case .ok: return .green
        case .offline: return .red
        }
    }
    private func statusHelp() -> String {
        let prov = store.settings.aiProvider == .local ? "Local" : "External"
        let host: String = {
            if store.settings.aiProvider == .local {
                let base = store.settings.aiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return URL(string: base)?.host ?? base
            } else {
                return URL(string: store.settings.aiExternalEndpoint)?.host ?? "external"
            }
        }()
        let st: String = {
            switch providerStatus { case .unknown: return "Unknown"; case .loading: return "Working"; case .ok: return "OK"; case .offline: return "Offline" }
        }()
        return "\(prov) • \(host) • \(st)"
    }
}
