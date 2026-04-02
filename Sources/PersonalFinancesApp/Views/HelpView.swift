import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Personal Finances Help")
                        .font(.title2.bold())
                    Text("Quick guide to the main screens and workflows.")
                        .foregroundStyle(.secondary)
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Getting Started")
                            .font(.headline)
                        Text("Use the sidebar to switch between Bills, Income, Accounts, and Transactions. Most screens have an Add button in the toolbar.")
                            .foregroundStyle(.secondary)
                        Text("Bills: track recurring payments and mark them paid. Income: track salaries and other recurring income.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Bank CSV Import")
                            .font(.headline)
                        Text("Import your bank CSV files to create a transaction history in the ledger.")
                            .foregroundStyle(.secondary)
                        Text("Where: Settings → Data → Import bank CSV, or during the onboarding wizard.")
                            .foregroundStyle(.secondary)
                        Text("Tip: balances are not synced from the bank. If you want to ignore ledger balances, enable manual forecast balance in Settings → Budgets.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Manual Forecast Balance")
                            .font(.headline)
                        Text("If you want to enter your real money manually, enable “Use this balance even with Accounts” in Settings → Budgets.")
                            .foregroundStyle(.secondary)
                        Text("When enabled, the app hides account balances and uses your manual forecast balance for planning.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Backups")
                            .font(.headline)
                        Text("You can export and import your data from Settings → Data. Your data stays on your device unless you enable iCloud sync.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Support")
                            .font(.headline)
                        if let url = URL(string: "https://github.com/Litas-dev/Mac") {
                            Link("Open GitHub Repository", destination: url)
                        }
                        Text("If something looks wrong after a bank import, re-import after clearing data, or import from Settings → Data.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
        }
        .frame(minWidth: 560, minHeight: 520)
    }
}

