import Foundation

// Odpowiednik SharedPreferences "dar_tools_prefs" z Androida.
enum Prefs {
    // UserDefaults jest wewnętrznie synchronizowany → bezpieczny globalnie.
    nonisolated(unsafe) private static let d = UserDefaults.standard
    private static let usersKey = "users_json"

    static var apiAddress: String {
        get { d.string(forKey: "api_address") ?? "" }
        set { d.set(newValue, forKey: "api_address") }
    }

    static var apilohelperApi: String {
        get { d.string(forKey: "apilohelper_api") ?? "" }
        set { d.set(newValue, forKey: "apilohelper_api") }
    }

    // Tryb dummy: losowe dane zamiast API (do screenshotów)
    static var dummyMode: Bool {
        get { d.bool(forKey: "dummy_mode") }
        set { d.set(newValue, forKey: "dummy_mode") }
    }

    static var autoRefreshBraki: Bool {
        get { d.bool(forKey: "auto_refresh_braki") }
        set { d.set(newValue, forKey: "auto_refresh_braki") }
    }

    static var updateAvailableVersion: String {
        get { d.string(forKey: "update_available_version") ?? "" }
        set { d.set(newValue, forKey: "update_available_version") }
    }

    static func loadUsers() -> [User] {
        guard let data = d.data(forKey: usersKey) else { return [] }
        return (try? JSONDecoder().decode([User].self, from: data)) ?? []
    }

    static func saveUsers(_ users: [User]) {
        guard let data = try? JSONEncoder().encode(users) else { return }
        d.set(data, forKey: usersKey)
    }
}
