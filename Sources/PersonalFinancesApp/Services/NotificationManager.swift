import Foundation
import UserNotifications
#if os(macOS)
import AppKit
#endif

final class NotificationManager: NSObject {
    static let shared = NotificationManager()
    private override init() {
        super.init()
        if Self.isRunningInAppBundle {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            registerCategories()
        }
    }

    enum Action: String {
        case logPayment = "LOG_PAYMENT"
        case skip = "SKIP"
    }

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        guard let center = self.center() else {
            completion(false)
            return
        }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            completion(granted)
        }
    }

    func registerCategories() {
        guard let center = self.center() else { return }
        let log = UNNotificationAction(identifier: Action.logPayment.rawValue, title: "Log Payment", options: [])
        let skip = UNNotificationAction(identifier: Action.skip.rawValue, title: "Skip", options: [])
        let category = UNNotificationCategory(identifier: "BILL_DUE", actions: [log, skip], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func scheduleAll(for bills: [Bill], settings: AppSettings? = nil) {
        guard let center = self.center() else { return }
        center.removeAllPendingNotificationRequests()
        
        // Always update the badge if possible
        updateDockBadge(for: bills, settings: settings)
        
        guard settings?.enableNotifications ?? true else { return }
        
        for bill in bills where !(bill.isSnoozedActive) && !bill.hiddenUntilEdited && !bill.isPaidFor(date: bill.nextDueDate) {
            schedule(for: bill, settings: settings)
        }
    }

    func schedule(for bill: Bill, settings: AppSettings? = nil) {
        guard let center = self.center() else { return }
        let content = UNMutableNotificationContent()
        content.title = "🔔  \(bill.name)"
        content.body = "Due \(format(date: bill.nextDueDate)) — \(format(amount: bill.amount, settings: settings))"
        content.sound = .default
        content.categoryIdentifier = "BILL_DUE"
        content.userInfo = ["billID": bill.id.uuidString]
        if let settings {
            let count = attentionCount(for: [bill], settings: settings)
            if count > 0 { content.badge = NSNumber(value: count) }
        }

        let cal = Calendar.current
        let days = settings?.reminderDays ?? 7
        let sevenDaysBefore = cal.date(byAdding: .day, value: -days, to: bill.nextDueDate) ?? bill.nextDueDate
        let now = Date()
        var fireDate = sevenDaysBefore
        if fireDate < now {
            // Fallback to same-day 9:00 if 7-days-before already passed
            fireDate = bill.nextDueDate
        }
        var comps = cal.dateComponents([.year, .month, .day], from: fireDate)
        comps.hour = 9
        comps.minute = 0
        let dateForTrigger = cal.date(from: comps) ?? fireDate
        
        // If the calculated fire date is in the past, don't schedule a trigger.
        // Instead, we might want to fire an immediate notification if the app just started
        // and a bill is overdue, but UNCalendarNotificationTrigger won't help with that.
        // We only schedule future notifications here.
        if dateForTrigger < now { return }

        let triggerDate = cal.dateComponents([.year, .month, .day, .hour, .minute], from: dateForTrigger)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(identifier: "BILL_DUE_\(bill.id.uuidString)", content: content, trigger: trigger)
        center.add(request)
    }

    func sendTest() {
        guard let center = self.center() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Test Bill Reminder"
        content.body = "This is how your due notifications will look."
        content.sound = .default
        content.categoryIdentifier = "BILL_DUE"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(identifier: "TEST_BILL_DUE", content: content, trigger: trigger)
        center.add(request)
    }

    func postBootstrapSchedule() {
        NotificationCenter.default.post(name: .bootstrapSchedule, object: nil)
    }

    private func format(amount: DecimalAmount, settings: AppSettings? = nil) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = settings?.displayCurrencyCode ?? amount.currencyCode
        return nf.string(for: amount.value as NSDecimalNumber) ?? "\(amount.value)"
    }
    private func format(date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: date)
    }
    
    private func attentionCount(for bills: [Bill], settings: AppSettings) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let daysWindow = settings.reminderDays
        return bills.reduce(0) { acc, b in
            if b.hiddenUntilEdited { return acc }
            if b.isSnoozedActive { return acc }
            if b.isPaidFor(date: b.nextDueDate) { return acc }
            
            let due = cal.startOfDay(for: b.nextDueDate)
            let delta = cal.dateComponents([.day], from: today, to: due).day ?? 0
            
            // Any bill that is overdue (delta < 0), due today (delta = 0), 
            // or due within the user's window (delta <= daysWindow)
            if delta <= daysWindow { return acc + 1 }
            
            return acc
        }
    }
    
    func updateDockBadge(for bills: [Bill], settings: AppSettings?) {
        let count: Int
        if let settings, settings.enableNotifications {
            count = attentionCount(for: bills, settings: settings)
        } else {
            count = 0
        }
        #if os(macOS)
        if Self.isRunningInAppBundle {
            DispatchQueue.main.async {
                NSApplication.shared.dockTile.badgeLabel = (count > 0) ? "\(count)" : nil
            }
        }
        #endif
    }
    
    private func center() -> UNUserNotificationCenter? {
        guard Self.isRunningInAppBundle else { return nil }
        return UNUserNotificationCenter.current()
    }
    
    private static var isRunningInAppBundle: Bool {
        let url = Bundle.main.bundleURL
        if url.pathExtension == "app" { return true }
        return url.path.contains(".app/")
    }
}

extension Notification.Name {
    static let bootstrapSchedule = Notification.Name("bootstrapSchedule")
    static let notificationLogPayment = Notification.Name("notificationLogPayment")
    static let notificationSkipBill = Notification.Name("notificationSkipBill")
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let idString = userInfo["billID"] as? String, let id = UUID(uuidString: idString) else { return }
        switch response.actionIdentifier {
        case Action.logPayment.rawValue:
            NotificationCenter.default.post(name: .notificationLogPayment, object: nil, userInfo: ["billID": id])
        case Action.skip.rawValue:
            NotificationCenter.default.post(name: .notificationSkipBill, object: nil, userInfo: ["billID": id])
        default:
            break
        }
    }
}
