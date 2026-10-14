import SwiftUI
import UserNotifications

@main
struct DarToolsIOSApp: App {
    init() {
        Notif.install()
    }

    var body: some Scene {
        WindowGroup {
            LoginView()
        }
    }
}
