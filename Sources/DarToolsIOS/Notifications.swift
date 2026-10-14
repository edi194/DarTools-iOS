import Foundation
import UserNotifications

// Powiadomienia lokalne (odpowiednik NotificationCompat z Androida).
// iOS nie ma tła w stylu Androida — pętle sprawdzające działają, dopóki aplikacja jest otwarta.
enum Notif {
    // Trwały uchwyt — centrum trzyma delegate słabo; bez tego powiadomienia z foreground znikają.
    nonisolated(unsafe) private static let delegate = ForegroundNotifDelegate()

    static func requestAuth() {
        UNUserNotificationCenter.current().delegate = delegate
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func install() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    // "[Baza] Znaleziono braki" / "... w Apilo" / "... w Baselinker", body z licznikami.
    // identifier per-baza → odświeża zamiast piętrzyć.
    static func braki(db: String, apiloOrders: Int, blOrders: Int) {
        let c = UNMutableNotificationContent()
        let title: String
        if apiloOrders > 0 && blOrders > 0 { title = "Znaleziono braki" }
        else if apiloOrders > 0 { title = "Znaleziono braki w Apilo" }
        else { title = "Znaleziono braki w Baselinker" }
        c.title = db.isEmpty ? title : "[\(db)] \(title)"
        var body = ""
        if apiloOrders > 0 { body += "Apilo: \(apiloOrders)" }
        if apiloOrders > 0 && blOrders > 0 { body += " · " }
        if blOrders > 0 { body += "Baselinker: \(blOrders)" }
        c.body = body
        c.sound = .default
        let req = UNNotificationRequest(identifier: "braki-\(db)", content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// Pokazuje powiadomienia też gdy appka jest otwarta (domyślnie iOS je połyka).
private final class ForegroundNotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// Wspólne sprawdzenie braków (apilo + baselinker) — dla pętli w BrakiView i na ekranie głównym.
enum BrakiAutoCheck {
    // nil = błąd/brak helpera; inaczej liczby zamówień z brakami (0/0 = brak braków)
    static func check(helper: String, db: String) async -> (apilo: Int, bl: Int)? {
        guard !helper.isEmpty, !Dummy.on else { return nil }
        let profile = PartApi.profileStripped(db)
        var apilo = 0
        var bl = 0
        if let orders = try? await OrdersApi.apiloOrders(helper: helper, profile: profile) { apilo = orders.count }
        if let orders = try? await OrdersApi.baselinkerOrders(helper: helper, profile: profile) { bl = orders.count }
        return (apilo, bl)
    }
}
