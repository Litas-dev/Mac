# Kivana (macOS)

Kivana is a native macOS SwiftUI app for tracking bills, incomes, accounts, goals, debts, and basic reporting.

## Version
- Current: 0.5.12 (pre-alpha)
- Versioning: Semantic Versioning (MAJOR.MINOR.PATCH)
- Build number: increments over time (used as CFBundleVersion)

## Features
- Bills management: due dates, recurrence, snooze, skip, log payments.
- Income tracking: next pay dates, filtering, receipts.
- Accounts + transactions: basic ledger and net worth.
- Goals + debts: simple tracking views.
- Notifications: reminders at 09:00 with actions (log payment / skip).
- Calendar sync (optional): mirrors upcoming bill due dates into Apple Calendar.
- AI command bar: quick parsing/execution of common actions + recent command suggestions.

## Build & Run
This repo is a Swift Package Manager macOS app (macOS 13+, Intel + Apple Silicon).

- Run using the script (recommended):

```bash
./Scripts/build_and_run.sh
```

- Open in Xcode:
  - Open `Package.swift` (or the included `Kivana.xcodeproj` if you prefer).

## Calendar Sync
- Enable in the app: Settings → Notifications → Calendar sync.
- The app creates/updates/removes all‑day events in a dedicated calendar (configurable name).
- To fully update/remove existing events, macOS needs Calendar permission set to Full Access.

## Data Storage
- Data is stored locally on disk (JSON repositories under Application Support).
- Import/export is available from Settings → Data.

## Development Workflow (GitHub)
This project is intended to be developed with normal Git commits and pushed to a private GitHub repo.

- Initialize Git locally (once):

```bash
git init
git branch -M main
git remote add origin https://github.com/Litas-dev/Mac.git
```

- Daily workflow:
  - Make changes
  - Commit locally
  - Push to GitHub

```bash
git add -A
git commit -m "Describe change"
git push -u origin main
```

If you prefer a UI, GitHub Desktop works well for “sync as you go” development.
