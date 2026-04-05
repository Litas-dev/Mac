# Kivana (Desktop)

Kivana is a cross-platform desktop app (Tauri + React) for tracking bills, incomes, accounts, goals, debts, and basic reporting.

## Version
- Current: 0.1.1
- Versioning: Semantic Versioning (MAJOR.MINOR.PATCH)

## Features
- Bills management: due dates, recurrence, snooze, skip, log payments.
- Income tracking: next pay dates, filtering, receipts.
- Accounts + transactions: basic ledger and net worth.
- Goals + debts: simple tracking views.
- Notifications + calendar export (ICS).
- AI command bar: quick parsing/execution of common actions + recent command suggestions.

## Build & Run
The desktop app lives in `pf-desktop/`.

```bash
cd pf-desktop
npm install
npm run tauri:dev
```

To produce installers/bundles:

```bash
cd pf-desktop
npm run tauri:build
```

## Data Storage
- Data is stored locally on disk (JSON under the app data directory).
- Import/export/backup is available from Settings.

## Legacy macOS App
The old native SwiftUI macOS implementation was archived to `old-macos-app.zip` and removed from the working tree to keep this repo focused on the cross-platform app.

## Development Workflow (GitHub)
This project uses normal Git version control.

```bash
git add -A
git commit -m "Describe change"
git push
```

Releases are tagged (example: `v0.1.1`).
