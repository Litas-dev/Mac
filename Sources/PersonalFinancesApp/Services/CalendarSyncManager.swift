@preconcurrency import EventKit
import Foundation

final class CalendarSyncManager {
    static let shared = CalendarSyncManager()
    
    private let queue = DispatchQueue(label: "pf.calendarsync")
    private let eventStore = EKEventStore()
    private let mappingStore = CalendarSyncMappingStore()
    private var pending: DispatchWorkItem?
    
    private init() {}
    
    func requestAccess() async -> Bool {
        if hasFullAccess() {
            return true
        }
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .denied || status == .restricted {
            return false
        }
        if status != .notDetermined {
            return hasFullAccess()
        }
        if #available(macOS 14.0, *) {
            return await withCheckedContinuation { cont in
                eventStore.requestFullAccessToEvents { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        } else {
            return await withCheckedContinuation { cont in
                eventStore.requestAccess(to: .event) { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        }
    }
    
    func scheduleSync(bills: [Bill], settings: AppSettings) {
        guard settings.calendarSyncEnabled else { return }
        queue.async {
            self.pending?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.syncNow(bills: bills, settings: settings)
            }
            self.pending = work
            self.queue.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }
    
    func removeAllSyncedEvents(bills: [Bill], settings: AppSettings) async -> Bool {
        let ok = await requestAccess()
        guard ok else { return false }
        let queue = self.queue
        let mappingStore = self.mappingStore
        let eventStore = self.eventStore
        
        return await withCheckedContinuation { cont in
            queue.async {
                var mapping = mappingStore.load()
                if mapping.isEmpty {
                    cont.resume(returning: true)
                    return
                }
                
                for (_, eventId) in mapping {
                    if let ev = eventStore.event(withIdentifier: eventId) {
                        try? eventStore.remove(ev, span: .thisEvent, commit: false)
                    }
                }
                do {
                    try eventStore.commit()
                    mapping.removeAll()
                    mappingStore.save(mapping)
                    cont.resume(returning: true)
                } catch {
                    cont.resume(returning: false)
                }
            }
        }
    }
    
    private func syncNow(bills: [Bill], settings: AppSettings) {
        guard hasFullAccess() else { return }
        
        let calendar: EKCalendar
        do {
            calendar = try ensureCalendar(named: settings.calendarSyncCalendarName)
        } catch {
            return
        }
        
        let desired = desiredEvents(bills: bills, settings: settings)
        var mapping = mappingStore.load()
        var usedKeys = Set<String>()
        
        for item in desired {
            usedKeys.insert(item.key)
            let existingId = mapping[item.key]
            let event: EKEvent
            if let existingId, let existing = eventStore.event(withIdentifier: existingId) {
                event = existing
            } else {
                event = EKEvent(eventStore: eventStore)
            }
            
            event.calendar = calendar
            event.title = item.title
            event.isAllDay = true
            let local = Calendar.current
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            var comps = local.dateComponents([.year, .month, .day], from: item.start)
            comps.timeZone = utc.timeZone
            let utcDayStart = utc.date(from: comps) ?? local.startOfDay(for: item.start)
            event.startDate = utcDayStart
            event.endDate = utc.date(byAdding: .day, value: 1, to: utcDayStart) ?? utcDayStart
            event.timeZone = nil
            event.notes = item.notes
            event.alarms = item.alarms
            
            do {
                try eventStore.save(event, span: .thisEvent, commit: false)
                if let id = event.eventIdentifier {
                    mapping[item.key] = id
                }
            } catch {
            }
        }
        
        let stale = mapping.keys.filter { !usedKeys.contains($0) }
        for key in stale {
            if let eventId = mapping[key], let ev = eventStore.event(withIdentifier: eventId) {
                try? eventStore.remove(ev, span: .thisEvent, commit: false)
            }
            mapping.removeValue(forKey: key)
        }
        
        do {
            try eventStore.commit()
            mappingStore.save(mapping)
        } catch {
        }
    }
    
    private func desiredEvents(bills: [Bill], settings: AppSettings) -> [DesiredEvent] {
        let cal = Calendar.current
        let now = Date()
        let end = cal.date(byAdding: .month, value: max(0, settings.calendarSyncMonthsAhead), to: now) ?? now
        let leadDays = max(0, settings.calendarSyncLeadDays)
        
        var out: [DesiredEvent] = []
        out.reserveCapacity(bills.count * 2)
        
        for bill in bills {
            if bill.hiddenUntilEdited { continue }
            if bill.isSnoozedActive { continue }
            if bill.recurrence == .once, !bill.payments.isEmpty { continue }
            
            var due = bill.nextDueDate
            while cal.startOfDay(for: due) <= cal.startOfDay(for: end) {
                if bill.isPaidFor(date: due) {
                    if bill.recurrence == .once { break }
                    due = bill.recurrence.advance(from: due)
                    continue
                }
                
                let day = cal.startOfDay(for: due)
                let key = bill.id.uuidString + "|" + isoDay(day)
                let title = bill.name
                let notes = "Amount: " + formatCurrency(amount: bill.amount) + "\nBill ID: " + bill.id.uuidString
                
                let alarms: [EKAlarm] = {
                    if leadDays <= 0 { return [] }
                    return [EKAlarm(relativeOffset: -Double(leadDays) * 86400)]
                }()
                
                out.append(DesiredEvent(key: key, title: title, start: day, notes: notes, alarms: alarms))
                
                if bill.recurrence == .once { break }
                due = bill.recurrence.advance(from: due)
            }
        }
        
        return out
    }
    
    private func ensureCalendar(named name: String) throws -> EKCalendar {
        if let existing = eventStore.calendars(for: .event).first(where: { $0.title == name }) {
            return existing
        }
        
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = name
        
        if let local = eventStore.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = local
        } else if let `default` = eventStore.defaultCalendarForNewEvents?.source {
            calendar.source = `default`
        } else if let any = eventStore.sources.first {
            calendar.source = any
        }
        
        try eventStore.saveCalendar(calendar, commit: true)
        return calendar
    }
    
    private func hasFullAccess() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }
    
    private func formatCurrency(amount: DecimalAmount) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = amount.currencyCode
        return nf.string(for: amount.value as NSDecimalNumber) ?? "\(amount.value)"
    }
    
    private func isoDay(_ date: Date) -> String {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]
        return df.string(from: date)
    }
    
    private struct DesiredEvent {
        let key: String
        let title: String
        let start: Date
        let notes: String
        let alarms: [EKAlarm]
    }
}

private final class CalendarSyncMappingStore {
    private let queue = DispatchQueue(label: "pf.calendarsync.mapping")
    
    func load() -> [String: String] {
        queue.sync {
            let url = fileURL()
            let data: Data?
            if let d = try? Data(contentsOf: url) {
                data = d
            } else if let d = try? Data(contentsOf: legacyFileURL()) {
                data = d
            } else {
                data = nil
            }
            guard let data else { return [:] }
            let decoded = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            if !decoded.isEmpty {
                saveUnlocked(decoded)
            }
            return decoded
        }
    }
    
    func save(_ mapping: [String: String]) {
        queue.sync {
            saveUnlocked(mapping)
        }
    }
    
    private func saveUnlocked(_ mapping: [String: String]) {
        guard let data = try? JSONEncoder().encode(mapping) else { return }
        try? data.write(to: fileURL(), options: .atomic)
    }
    
    private func fileURL() -> URL {
        let fm = FileManager.default
        let dir = PersistencePaths.localBaseDirectory()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("CalendarSync.json")
    }
    
    private func legacyFileURL() -> URL {
        PersistencePaths.legacyLocalBaseDirectory()
            .appendingPathComponent("CalendarSync.json")
    }
}
